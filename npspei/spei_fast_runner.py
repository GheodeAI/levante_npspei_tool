import argparse
import numpy as np
import xarray as xr
import rpy2.robjects as ro
from rpy2.robjects import numpy2ri
import logging
from tqdm import tqdm
import os
import json
import time
import shutil

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
numpy2ri.activate()

def load_r_environment(r_script_path):
    if not os.path.exists(r_script_path):
        raise FileNotFoundError(f"R script not found: {r_script_path}")
    ro.r(f'source("{r_script_path}")')
    return ro.r['np.spei_batch']

def process_fast(input_nc, output_nc, r_script, var_name, batch_size=500, checkpoint_minutes=20, **spei_kwargs):
    # --- 1. Setup Paths ---
    # Create a temp directory specifically for this output file to avoid collisions
    temp_dir = f"{output_nc}_temp_data"
    os.makedirs(temp_dir, exist_ok=True)
    
    memmap_path = os.path.join(temp_dir, "data.dat")
    meta_path = os.path.join(temp_dir, "metadata.json")
    
    # --- 2. Load Input Data ---
    logging.info(f"Reading input data from {input_nc}...")
    # using chunks={} ensures we can load it efficiently, or .load() to put in RAM
    # Given your dimensions (900x1920xTime), 32GB RAM is plenty to hold input in memory.
    ds_in = xr.open_dataset(input_nc)
    
    # Check if we can load to memory (Try/Except for safety)
    try:
        # Loading input to RAM speeds up reading by 100x compared to disk seeking
        input_data = ds_in[var_name].values 
        logging.info("Input data loaded into memory.")
    except Exception as e:
        logging.warning(f"Could not load input to RAM ({e}). processing will be slower.")
        input_data = ds_in[var_name] # Fallback to lazy loading
        
    times = ds_in.time.values
    lats = ds_in.lat.values
    lons = ds_in.lon.values
    
    n_time, n_lat, n_lon = input_data.shape
    total_points = n_lat * n_lon
    
    # --- 3. Initialize/Load Checkpoint (Memmap) ---
    # We use np.memmap to store results on disk as a raw binary array
    # This acts as our persistent storage.
    
    if os.path.exists(meta_path) and os.path.exists(memmap_path):
        logging.info("Found existing checkpoint. Resuming...")
        with open(meta_path, 'r') as f:
            meta = json.load(f)
        start_index = meta['last_index']
        # Open in read/write mode
        output_memmap = np.memmap(memmap_path, dtype='float32', mode='r+', shape=(n_time, n_lat, n_lon))
    else:
        logging.info("Starting fresh processing...")
        start_index = 0
        # Create new memmap file, filled with zeros (we will handle NaNs logic)
        output_memmap = np.memmap(memmap_path, dtype='float32', mode='w+', shape=(n_time, n_lat, n_lon))
        # Initialize with NaNs (optional, but safer for skipped ocean points)
        # Note: Filling a large memmap takes time, so we might skip this and just write NaNs where needed,
        # but initializing ensures skipped points are NaNs. 
        # OPTIMIZATION: Instead of filling, we just trust that 'valid_mask' logic 
        # and we fill the rest with NaNs at the end or assume 0 if not touched?
        # Better: Fill with NaNs now. It takes a few seconds.
        output_memmap[:] = np.nan
        output_memmap.flush()

    # --- 4. Prepare R Environment ---
    try:
        r_batch_func = load_r_environment(r_script)
    except Exception as e:
        logging.error(f"R Error: {e}")
        return

    # Setup time string for R
    # Assuming standard pandas/xarray datetime handling
    try:
        ts_start = f"{pd.to_datetime(times[0]).year}-{pd.to_datetime(times[0]).month}"
    except:
        # Fallback for cftime or other formats
        ts_start = "1981-01" # Adjust logic if needed or pass as arg

    # --- 5. Processing Loop ---
    current_idx = start_index
    last_sync_time = time.time()
    
    # Helper to flatten/unflatten
    # We iterate flat, but access 3D array
    
    pbar = tqdm(total=total_points, initial=start_index, unit="pixel")
    
    while current_idx < total_points:
        end_idx = min(current_idx + batch_size, total_points)
        batch_len = end_idx - current_idx
        
        # Get indices
        flat_indices = np.arange(current_idx, end_idx)
        rows, cols = np.unravel_index(flat_indices, (n_lat, n_lon))
        
        # A. Extract Batch Input
        # Advanced indexing works on numpy arrays in RAM
        # shape: (time, batch_len)
        # If input_data is xarray/dask, this triggers a read. If numpy, it's instant.
        batch_input = input_data[:, rows, cols] 
        
        # B. Check for Data (Skip Ocean)
        # Check along time axis (axis 0)
        valid_mask = ~np.isnan(batch_input).all(axis=0)
        
        if np.any(valid_mask):
            # Only send valid pixels to R
            valid_data = batch_input[:, valid_mask]
            
            try:
                # Prepare Args
                kwargs = {
                    'freq': 12, 
                    'ts_start': ts_start,
                    'scale': spei_kwargs.get('scale', 3)
                }
                if 'ref_start' in spei_kwargs: kwargs['ref.start'] = spei_kwargs['ref_start']
                if 'ref_end' in spei_kwargs: kwargs['ref.end'] = spei_kwargs['ref_end']

                # Call R
                r_result = r_batch_func(valid_data, **kwargs)
                r_result_np = np.array(r_result)
                
                # Write to Output Memmap
                # We map back the valid results to their positions
                # Note: memmap supports advanced indexing for assignment
                
                # Create a holder for this batch
                batch_output = np.full((n_time, batch_len), np.nan, dtype='float32')
                batch_output[:, valid_mask] = r_result_np
                
                # Write back to memmap
                # (Slightly slower than slice, but necessary for batching arbitrary 2D points)
                output_memmap[:, rows, cols] = batch_output

            except Exception as e:
                logging.error(f"Error in batch {current_idx}: {e}")
        
        # C. Checkpoint
        current_time = time.time()
        if (current_time - last_sync_time) > (checkpoint_minutes * 60):
            logging.info(f"Syncing checkpoint at index {end_idx}...")
            output_memmap.flush() # Force write to disk
            with open(meta_path, 'w') as f:
                json.dump({'last_index': int(end_idx)}, f)
            last_sync_time = current_time
            
        current_idx = end_idx
        pbar.update(batch_len)
        
    pbar.close()
    
    # --- 6. Finalize: Create NetCDF ---
    logging.info("Processing complete. Creating final NetCDF file...")
    
    # Create xarray dataset from the memmap
    # We reopen the memmap to ensure clean state or just use the array
    
    ds_out = xr.Dataset(
        data_vars={
            "spei": (("time", "lat", "lon"), output_memmap)
        },
        coords={
            "time": times,
            "lat": lats,
            "lon": lons
        }
    )
    
    # Add Attributes
    ds_out.spei.attrs = {
        "description": "Non-parametric SPEI",
        "scale": spei_kwargs.get('scale', 3),
        "source": input_nc
    }
    
    # Save to NetCDF
    # This is the ONLY time we do a heavy NetCDF write
    ds_out.to_netcdf(output_nc)
    logging.info(f"Saved final file: {output_nc}")
    
    # --- 7. Cleanup ---
    try:
        # Close memmap reference
        del output_memmap
        # Remove temp directory
        shutil.rmtree(temp_dir)
        logging.info("Cleaned up temporary files.")
    except Exception as e:
        logging.warning(f"Could not remove temp files: {e}")

if __name__ == "__main__":
    import pandas as pd # Needed for timestamp parsing inside main
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--r-script', required=True)
    parser.add_argument('--scale', type=int, default=3)
    parser.add_argument('--ref-start', type=int, default=1981)
    parser.add_argument('--ref-end', type=int, default=2010)
    
    args = parser.parse_args()
    
    process_fast(
        args.input, 
        args.output, 
        args.r_script, 
        var_name="wb",
        batch_size=500,
        scale=args.scale,
        ref_start=args.ref_start,
        ref_end=args.ref_end
    )