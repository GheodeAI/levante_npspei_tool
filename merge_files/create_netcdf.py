import numpy as np
import xarray as xr
import json
from pathlib import Path
import re
import os

def create_netcdf(output_dir, output_file):
    """Reconstruct NetCDF from individual grid point files with checkpoint support"""
    output_dir = Path(output_dir)
    grid_dir = output_dir / 'grid_points'
    
    # Load metadata
    with open(output_dir / 'metadata.json') as f:
        meta = json.load(f)
    
    # Load coordinate data
    time = np.load(output_dir / 'time.npy')
    lats = np.load(output_dir / 'lat.npy')
    lons = np.load(output_dir / 'lon.npy')
    
    # Determine output path
    output_path = output_dir / output_file
    
    # Initialize or load existing checkpoint
    if output_path.exists():
        print(f"Loading checkpoint from {output_path}")
        try:
            # Try to load existing NetCDF
            ds = xr.open_dataset(output_path)
            spei_data = ds['spei'].values.copy()
            ds.close()
            
            # Create a set of already processed grid points
            processed_points = set()
            for i in range(len(lats)):
                for j in range(len(lons)):
                    # Check if this grid point has any non-NaN data
                    if not np.all(np.isnan(spei_data[:, i, j])):
                        processed_points.add((i, j))
            print(f"Found {len(processed_points)} already processed grid points")
            
        except Exception as e:
            print(f"Error loading checkpoint: {e}. Starting from scratch.")
            spei_data = np.empty((len(time), len(lats), len(lons)), dtype=np.float32)
            spei_data[:] = np.nan
            processed_points = set()
    else:
        # Initialize empty array if no checkpoint exists
        spei_data = np.empty((len(time), len(lats), len(lons)), dtype=np.float32)
        spei_data[:] = np.nan
        processed_points = set()
        print("No checkpoint found. Starting from scratch.")
    
    # Get all grid point files
    # grid_files = list(grid_dir.glob('spei_*.npy')) # zone4
    grid_files = sorted(list(grid_dir.glob('spei_*.npy')))
    print(f"Found {len(grid_files)} grid point files")
    
    # Track progress
    total_files = len(grid_files)
    processed_count = 0
    skipped_count = 0
    failed_files = []
    
    # Process each grid point file
    for file_path in grid_files:
        # Extract i,j indices from filename
        match = re.match(r'spei_(\d+)_(\d+)\.npy', file_path.name)
        if not match:
            continue
            
        i = int(match.group(1))
        j = int(match.group(2))
        
        # Skip if already processed
        if (i, j) in processed_points:
            skipped_count += 1
            if skipped_count % 100 == 0:  # Print progress every 100 skipped files
                print(f"Skipped {skipped_count} already processed files...")
            continue
        
        try:
            # Load SPEI values
            spei_values = np.load(file_path)
            
            # Validate dimensions
            if len(spei_values) == len(time):
                spei_data[:, i, j] = spei_values
                processed_points.add((i, j))
                processed_count += 1
                
                # Save checkpoint every N processed files
                checkpoint_interval = min(100, max(10, total_files // 20))  # Dynamic interval
                if processed_count % checkpoint_interval == 0:
                    print(f"Processed {processed_count}/{total_files} files. Saving checkpoint...")
                    
                    # Create temporary checkpoint file
                    temp_output = output_dir / f"{output_file}.temp"
                    
                    # Create xarray Dataset with current progress
                    ds = xr.Dataset(
                        data_vars={
                            "spei": (["time", "lat", "lon"], spei_data)
                        },
                        coords={
                            "time": time,
                            "lat": lats,
                            "lon": lons
                        },
                        attrs={
                            "description": "Non-parametric SPEI",
                            "scale": meta['scale'],
                            "reference_period": f"{meta['ref_start']}-{meta['ref_end']}",
                            "source_file": meta['input_file'],
                            "checkpoint_progress": f"{processed_count}/{total_files}",
                            "checkpoint_timestamp": np.datetime64('now').astype(str)
                        }
                    )
                    
                    # Save to temporary file
                    ds.to_netcdf(temp_output)
                    
                    # Replace main file with temporary
                    if output_path.exists():
                        output_path.unlink()
                    temp_output.rename(output_path)
                    
                    print(f"Checkpoint saved: {processed_count}/{total_files} files processed")
                    
            else:
                print(f"Warning: Dimension mismatch for file {file_path.name}. Expected {len(time)} timesteps, got {len(spei_values)}")
                failed_files.append(file_path.name)
                
        except Exception as e:
            print(f"Error processing {file_path.name}: {e}")
            failed_files.append(file_path.name)
    
    # Final save with complete data
    print(f"\nProcessing complete. Processed: {processed_count}, Skipped: {skipped_count}, Failed: {len(failed_files)}")
    
    if failed_files:
        print(f"Failed files: {failed_files}")
    
    # Create final xarray Dataset
    ds = xr.Dataset(
        data_vars={
            "spei": (["time", "lat", "lon"], spei_data)
        },
        coords={
            "time": time,
            "lat": lats,
            "lon": lons
        },
        attrs={
            "description": "Non-parametric SPEI",
            "scale": meta['scale'],
            "reference_period": f"{meta['ref_start']}-{meta['ref_end']}",
            "source_file": meta['input_file'],
            "processing_complete": "True",
            "processed_grid_points": f"{processed_count}/{total_files}"
        }
    )
    
    # Save final NetCDF
    ds.to_netcdf(output_path)
    print(f"Saved reconstructed SPEI data to {output_path}")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('-od', '--output-dir', dest='output_dir', help='Directory with processed data')
    parser.add_argument('-of', '--output-file', dest='output_file', default='spei_output.nc' , help='Output netCDF file')
    args = parser.parse_args()
    create_netcdf(args.output_dir, args.output_file)