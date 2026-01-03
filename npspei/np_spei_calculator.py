import argparse
import json
import os
import sys
import warnings
import logging
from pathlib import Path
import numpy as np
import xarray as xr
import pandas as pd
import rpy2.robjects as ro
from rpy2.robjects import pandas2ri, numpy2ri
from rpy2.robjects.packages import importr
from tqdm import tqdm
from rpy2.robjects.conversion import localconverter

# Suppress warnings and configure logging
warnings.filterwarnings("ignore")
logging.basicConfig(level=logging.INFO, 
                    format='%(asctime)s - %(levelname)s - %(message)s')

# Activate automatic conversion between pandas/numpy and R objects
pandas2ri.activate()
numpy2ri.activate()

def load_r_code(r_script_path):
    """Load the R code containing the np.spei function."""
    try:
        # Set custom R library path
        ro.r('.libPaths(c("~/R/x86_64-pc-linux-gnu-library/4.1/", .libPaths()))')
        
        # Load required R packages
        ro.r('library(zoo)')
        ro.r('library(lubridate)')
        ro.r('library(SPEI)')
        
        # Source the R script
        if not Path(r_script_path).exists():
            raise FileNotFoundError(f"R script not found at {r_script_path}")
        ro.r(f'source("{r_script_path}")')
        logging.info("R environment initialized successfully")
        return True
    except Exception as e:
        logging.error(f"Error initializing R environment: {e}")
        return False

def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser(
        description='Calculate non-parametric SPEI using R code on xarray data.'
    )
    parser.add_argument('input_file', type=str, 
                        help='Path to input NetCDF file')
    parser.add_argument('-c', '--config', type=str,
                        help='Path to JSON config file')
    parser.add_argument('-v', '--var-name', type=str, 
                        help='Variable name in NetCDF file')
    parser.add_argument('-s', '--scale', type=int, 
                        help='SPEI scale parameter')
    parser.add_argument('-rs', '--ref-start', type=int,
                        help='Start year for reference period')
    parser.add_argument('-re', '--ref-end', type=int,
                        help='End year for reference period')
    parser.add_argument('-r', '--r-script', type=str, default='np_spei.R',
                        help='Path to R script containing np.spei function')
    parser.add_argument('-o', '--output-dir', type=str, required=True,
                        help='Output directory for numpy files and metadata')
    parser.add_argument('--grid-index', type=int, default=None,
                        help='Grid index to process (for array jobs)')
    parser.add_argument('--grid-size', type=int, default=None,
                        help='Total grid size (for array jobs)')
    args = parser.parse_args()
    
    # Load configuration from JSON if provided
    config = {}
    if args.config:
        try:
            with open(args.config) as f:
                config = json.load(f)
            logging.info(f"Loaded configuration from {args.config}")
        except Exception as e:
            logging.error(f"Error loading config file: {e}")
            sys.exit(1)
    
    # Override config with command-line arguments where provided
    params = {
        'var_name': args.var_name,
        'scale': args.scale,
        'ref_start': args.ref_start,
        'ref_end': args.ref_end
    }
    for key, value in params.items():
        if value is not None:  # Command-line takes priority
            config[key] = value
        elif key not in config:  # Set default if not in config
            config[key] = None
    
    # Validate required parameters
    if not config.get('var_name'):
        logging.error("Variable name not provided in config or command line!")
        sys.exit(1)
    
    # Create output directory
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    logging.info(f"Output directory: {output_dir}")
    
    # Load NetCDF data
    try:
        ds = xr.open_dataset(args.input_file)
        da = ds[config['var_name']]
        times = da.time.values
        lats = da.lat.values
        lons = da.lon.values
        logging.info(f"Loaded data: {da.dims}")
    except Exception as e:
        logging.error(f"Error loading NetCDF: {e}")
        sys.exit(1)
    
    # Calculate grid dimensions
    n_lats = len(lats)
    n_lons = len(lons)
    total_points = n_lats * n_lons
    
    # Save metadata for reconstruction (only if not in array mode)
    if (args.grid_index is None) or (args.grid_index == 0):
        metadata = {
            'original_shape': da.shape,
            'time': [str(t) for t in pd.to_datetime(times)],
            'lat': lats.tolist(),
            'lon': lons.tolist(),
            'scale': config['scale'],
            'ref_start': config['ref_start'],
            'ref_end': config['ref_end'],
            'var_name': config['var_name'],
            'input_file': args.input_file
        }
        with open(output_dir / 'metadata.json', 'w') as f:
            json.dump(metadata, f, indent=2)
        
        # Save coordinate arrays
        np.save(output_dir / 'time.npy', times)
        np.save(output_dir / 'lat.npy', lats)
        np.save(output_dir / 'lon.npy', lons)
        logging.info("Saved metadata and coordinate files")
    
    # Load R code
    if not load_r_code(args.r_script):
        sys.exit(1)
    
    # Get R function
    try:
        np_spei_py = ro.r['np.spei_py']
        logging.info("Loaded np.spei_py function from R")
    except Exception as e:
        logging.error(f"Error loading R function: {e}")
        sys.exit(1)
    
    # Prepare time series metadata for R
    times_pd = pd.to_datetime(times)
    freq = pd.infer_freq(times_pd)
    frequency = 12 #if freq == 'M' else 365 if freq == 'D' else 1
    start_time = times_pd[0]
    ts_start = f'{start_time.year}-{start_time.month}'
    
    # Create directory for individual grid point results
    grid_dir = output_dir / 'grid_points'
    grid_dir.mkdir(exist_ok=True)
    logging.info(f"Created grid point directory: {grid_dir}")
    
    # Process grid points based on mode
    if args.grid_index is not None:
        # Array job mode - process a single grid point
        if args.grid_index >= total_points:
            logging.error(f"Grid index {args.grid_index} is out of range (0-{total_points-1})")
            sys.exit(1)
        
        # Calculate i and j from grid index
        i = args.grid_index // n_lons
        j = args.grid_index % n_lons
        
        logging.info(f"Processing grid point {args.grid_index} (i={i}, j={j})")
        
        # Create unique filename for this grid point
        output_path = grid_dir / f"spei_{i}_{j}.npy"
        
        # Skip if file already exists
        if output_path.exists():
            logging.info(f"Grid point {i},{j} already processed, skipping")
            sys.exit(0)
        
        # Extract time series for this grid point
        data_1d = da[:, i, j].values
        
        # Skip if all NaN
        if np.all(np.isnan(data_1d)):
            # Save empty result file for consistency
            np.save(output_path, np.full(len(data_1d), np.nan))
            logging.info(f"Grid point {i},{j} contains only NaN values")
            sys.exit(0)
        
        try:
            # Convert to R vector
            with localconverter(ro.default_converter + numpy2ri.converter):
                r_ts = ro.conversion.py2rpy(data_1d)
            
            # Prepare arguments for R function
            kwargs = {'scale': config['scale']}
            if config['ref_start'] and config['ref_end']:
                kwargs['ref.start'] = config['ref_start']
                kwargs['ref.end'] = config['ref_end']
            
            # Calculate SPEI
            spei_result = np_spei_py(r_ts, frequency, ts_start, **kwargs)
            
            # Convert back to numpy
            with localconverter(ro.default_converter + numpy2ri.converter):
                spei_values = ro.conversion.rpy2py(spei_result)
            
            # Save results for this grid point
            np.save(output_path, spei_values.astype(np.float32))
            logging.info(f"Successfully processed grid point {i},{j}")
            
        except Exception as e:
            logging.error(f"Error at grid point ({i}, {j}): {str(e)}")
            # Save NaN array on error
            np.save(output_path, np.full(len(data_1d), np.nan))
            sys.exit(1)
    
    else:
        # Standard mode - process all grid points
        logging.info(f"Processing all {total_points} grid points")
        
        with tqdm(total=total_points, desc="Processing grid points") as pbar:
            for i in range(n_lats):
                for j in range(n_lons):
                    # Create unique filename for this grid point
                    output_path = grid_dir / f"spei_{i}_{j}.npy"
                    
                    # Skip if file already exists (for restart capability)
                    if output_path.exists():
                        pbar.update(1)
                        continue
                    
                    # Extract time series for this grid point
                    data_1d = da[:, i, j].values
                    
                    # Skip if all NaN
                    if np.all(np.isnan(data_1d)):
                        # Save empty result file for consistency
                        np.save(output_path, np.full(len(data_1d), np.nan))
                        pbar.update(1)
                        continue
                    
                    try:
                        # Convert to R vector
                        with localconverter(ro.default_converter + numpy2ri.converter):
                            r_ts = ro.conversion.py2rpy(data_1d)
                        
                        # Prepare arguments for R function
                        kwargs = {'scale': config['scale']}
                        if config['ref_start'] and config['ref_end']:
                            kwargs['ref.start'] = config['ref_start']
                            kwargs['ref.end'] = config['ref_end']
                        
                        # Calculate SPEI
                        spei_result = np_spei_py(r_ts, frequency, ts_start, **kwargs)
                        
                        # Convert back to numpy
                        with localconverter(ro.default_converter + numpy2ri.converter):
                            spei_values = ro.conversion.rpy2py(spei_result)
                        
                        # Save results for this grid point
                        np.save(output_path, spei_values.astype(np.float32))
                        
                    except Exception as e:
                        logging.error(f"Error at grid point ({i}, {j}): {str(e)}")
                        # Save NaN array on error
                        np.save(output_path, np.full(len(data_1d), np.nan))
                    
                    pbar.update(1)
    
    # Clean up
    ds.close()
    logging.info(f"Processing complete. Results saved in: {grid_dir}")

if __name__ == '__main__':
    main()