import numpy as np
import xarray as xr
from pathlib import Path
import pandas as pd
import rpy2.robjects as ro
from rpy2.robjects import pandas2ri
import netCDF4 as nc

def main(output_dir, output_file):
    # Activate R-Python conversion
    pandas2ri.activate()
    
    # Load RDS file
    readRDS = ro.r['readRDS']
    metadata = readRDS(str(Path(output_dir) / "metadata.rds"))
    
    # Extract metadata
    lat = np.array(metadata[0])
    lon = np.array(metadata[1])
    time_values = np.array(metadata[2])
    scale = metadata[3]
    ref_start = metadata[4][0] if not isinstance(metadata[4], type(ro.r('NULL'))) else None
    ref_end = metadata[5][0] if not isinstance(metadata[5], type(ro.r('NULL'))) else None
    time_units = metadata[6][0]
    time_calendar = metadata[7][0]
    
    # Create time coordinate
    time_var = nc.num2date(
        time_values, 
        units=time_units,
        calendar=time_calendar
    )
    
    # Create empty SPEI array
    ntime = len(time_values)
    nlat = len(lat)
    nlon = len(lon)
    spei_data = np.empty((ntime, nlat, nlon), dtype=np.float32)
    spei_data[:] = np.nan
    
    # Load individual grid points
    for i in range(nlat):
        for j in range(nlon):
            npy_path = Path(output_dir) / f"spei_{i}_{j}.npy"
            if npy_path.exists() and npy_path.stat().st_size > 0:
                try:
                    # Load numpy file
                    data = np.load(npy_path)
                    spei_data[:, i, j] = data
                except Exception as e:
                    print(f"Error loading {npy_path}: {str(e)}")
    
    # Create dataset with datetime objects
    ds = xr.Dataset(
        data_vars={
            'spei': (('time', 'lat', 'lon'), spei_data)
        },
        coords={
            'time': time_var,  # Use datetime objects
            'lat': lat,
            'lon': lon
        }
    )
    
    # Add SPEI attributes
    ds['spei'].attrs = {
        'long_name': 'Non-parametric Standardized Precipitation Evapotranspiration Index',
        'units': 'dimensionless',
        'scale': scale,
        'reference_start': ref_start if ref_start else 'None',
        'reference_end': ref_end if ref_end else 'None'
    }
    
    # Set time attributes
    ds['time'].attrs = {
        'units': time_units,
        'calendar': time_calendar
    }
    
    # Add global attributes
    ds.attrs = {
        'title': 'SPEI Calculation Results',
        'source': f'Processed from {output_dir}',
        'history': f'Created {pd.Timestamp.now().isoformat()}'
    }
    
    # Save to NetCDF with explicit encoding
    encoding = {
        'spei': {
            'zlib': True,
            'complevel': 5,
            'dtype': 'float32'
        },
        'lat': {'dtype': 'float32'},
        'lon': {'dtype': 'float32'}
    }
    
    ds.to_netcdf(output_file, encoding=encoding)
    print(f"Saved results to {output_file}")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--output-file', required=True)
    args = parser.parse_args()
    main(args.output_dir, args.output_file)