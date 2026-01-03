import numpy as np
import xarray as xr
import json
from pathlib import Path
import re

def create_netcdf(output_dir, output_file):
    """Reconstruct NetCDF from individual grid point files"""
    output_dir = Path(output_dir)
    grid_dir = output_dir / 'grid_points'
    
    # Load metadata
    with open(output_dir / 'metadata.json') as f:
        meta = json.load(f)
    
    # Load coordinate data
    time = np.load(output_dir / 'time.npy')
    lats = np.load(output_dir / 'lat.npy')
    lons = np.load(output_dir / 'lon.npy')
    
    # Initialize empty array for SPEI data
    spei_data = np.empty((len(time), len(lats), len(lons)), dtype=np.float32)
    spei_data[:] = np.nan
    
    # Get all grid point files
    grid_files = list(grid_dir.glob('spei_*.npy'))
    
    # Process each grid point file
    for file_path in grid_files:
        # Extract i,j indices from filename
        match = re.match(r'spei_(\d+)_(\d+)\.npy', file_path.name)
        if not match:
            continue
            
        i = int(match.group(1))
        j = int(match.group(2))
        
        # Load SPEI values
        spei_values = np.load(file_path)
        
        # Store in main array
        if len(spei_values) == len(time):
            spei_data[:, i, j] = spei_values
    
    # Create xarray Dataset
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
            "source_file": meta['input_file']
        }
    )
    
    # Save to NetCDF
    output_path = output_dir / output_file
    ds.to_netcdf(output_path)
    print(f"Saved reconstructed SPEI data to {output_path}")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('-od', '--output-dir', dest='output_dir', help='Directory with processed data')
    parser.add_argument('-of', '--output-file', dest='output_file', default='spei_output.nc' , help='Output netCDF file')
    args = parser.parse_args()
    create_netcdf(args.output_dir, args.output_file)