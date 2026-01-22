from __future__ import annotations
import xarray as xr
import numpy as np
from pathlib import Path
import argparse


def main(zone:int=5):
    months = ["01_January", "02_February", "03_March", "04_April", "05_May", "06_June", "07_July", "09_September", "10_October", "11_November", "12_December"]
    sets_data = ['training', "testing"]
    #sets_data = ['training']
    ensembles = range(1,26)

    #for zone in range(3,6):
    print(f'Zone: {zone}')
    for ens in ensembles:
        print(f'Ens: {ens}')
        Path(f"./data/zone{zone}/ens{ens:02d}/").mkdir(parents=True, exist_ok=True)
        Path(f"./data/zone{zone}/ens{ens:02d}/pr_model/").mkdir(parents=True, exist_ok=True)
        Path(f"./data/zone{zone}/ens{ens:02d}/tn_model/").mkdir(parents=True, exist_ok=True)
        for month in months:
            Path(f"./data/zone{zone}/ens{ens:02d}/pr_model/{month}/").mkdir(parents=True, exist_ok=True)
            for set_data in sets_data:
                if zone == 1:
                    data1 = xr.open_dataset(f"/work/bb1478/Darrab/downscaling/models/pr_model/zone1/ens{ens:02d}/{month}/ecmwf_ens{ens:02d}_zone1_pr_{'1993_2014' if set_data=='training' else '2015_2015'}_{month[:2]}_00_downscaled_{set_data}.nc")
                    data6 = xr.open_dataset(f"/work/bb1478/Darrab/downscaling/models/pr_model/zone6/ens{ens:02d}/{month}/ecmwf_ens{ens:02d}_zone6_pr_{'1993_2014' if set_data=='training' else '2015_2015'}_{month[:2]}_00_downscaled_{set_data}.nc")
    
                    data1 = data1.sel(lon=slice(18,45), lat=slice(55.008333,48))
                    data6 = data6.sel(lon=slice(18,45), lat=slice(60,55))
    
                    data = xr.concat((data1,data6), dim='lat')
                elif zone == 2:
                    data1 = xr.open_dataset(f"/work/bb1478/Darrab/downscaling/models/pr_model/zone1/ens{ens:02d}/{month}/ecmwf_ens{ens:02d}_zone1_pr_{'1993_2014' if set_data=='training' else '2015_2015'}_{month[:2]}_00_downscaled_{set_data}.nc")
                    #data2 = xr.open_dataset(f"/work/bb1478/Darrab/downscaling/models/pr_model/zone2/ens{ens:02d}/{month}/ecmwf_ens{ens:02d}_zone2_pr_{'1993_2014' if set_data=='training' else '2015_2015'}_{month[:2]}_00_downscaled_{set_data}.nc")
                    data2 = xr.open_dataset(f"/work/bb1478/Darrab/bias_correction/bc_medwsa/Pr/zone2/ens{ens:02d}/outputs/bc_medewsa_{'c' if set_data == 'training' else 'v'}al_pr_daily_{'1993-2014' if set_data=='training' else '2015-2015'}_{month[:2]}.nc")
    
                    data1 = data1.sel(lon=slice(18,45), lat=slice(55.008333,48))
                    data2 = data2.sel(lon=slice(18,45), lat=slice(50,47))
    
                    data = xr.concat((data1,data2), dim='lat')
                elif zone == 3:
                    data5 = xr.open_dataset(f"/work/bb1478/Darrab/downscaling/models/pr_model/zone5/ens{ens:02d}/{month}/ecmwf_ens{ens:02d}_zone5_pr_{'1993_2014' if set_data=='training' else '2015_2015'}_{month[:2]}_00_downscaled_{set_data}.nc")
                    data6 = xr.open_dataset(f"/work/bb1478/Darrab/downscaling/models/pr_model/zone6/ens{ens:02d}/{month}/ecmwf_ens{ens:02d}_zone6_pr_{'1993_2014' if set_data=='training' else '2015_2015'}_{month[:2]}_00_downscaled_{set_data}.nc")
    
                    data5 = data5.sel(lon=slice(2,32), lat=slice(72,58))
                    data6 = data6.sel(lon=slice(32,45), lat=slice(72,58))
    
                    data = xr.concat((data5,data6), dim='lon')
                elif zone == 4:
                    data5 = xr.open_dataset(f"/work/bb1478/Darrab/downscaling/models/pr_model/zone5/ens{ens:02d}/{month}/ecmwf_ens{ens:02d}_zone5_pr_{'1993_2014' if set_data=='training' else '2015_2015'}_{month[:2]}_00_downscaled_{set_data}.nc")
                    data4 = xr.open_dataset(f"/work/bb1478/Darrab/downscaling/models/pr_model/zone4/ens{ens:02d}/{month}/ecmwf_ens{ens:02d}_zone4_pr_{'1993_2014' if set_data=='training' else '2015_2015'}_{month[:2]}_00_downscaled_{set_data}.nc")
                    data1 = xr.open_dataset(f"/work/bb1478/Darrab/downscaling/models/pr_model/zone1/ens{ens:02d}/{month}/ecmwf_ens{ens:02d}_zone1_pr_{'1993_2014' if set_data=='training' else '2015_2015'}_{month[:2]}_00_downscaled_{set_data}.nc")
                    #data2 = xr.open_dataset(f"/work/bb1478/Darrab/downscaling/models/pr_model/zone2/ens{ens:02d}/{month}/ecmwf_ens{ens:02d}_zone2_pr_{'1993_2014' if set_data=='training' else '2015_2015'}_{month[:2]}_00_downscaled_{set_data}.nc")
                    data2 = xr.open_dataset(f"/work/bb1478/Darrab/bias_correction/bc_medwsa/Pr/zone2/ens{ens:02d}/outputs/bc_medewsa_{'c' if set_data == 'training' else 'v'}al_pr_daily_{'1993-2014' if set_data=='training' else '2015-2015'}_{month[:2]}.nc")
    
                    data5 = data5.sel(lon=slice(15,20), lat=slice(60,55))
                    data4 = data4.sel(lat=slice(60,43))
                    data1 = data1.sel(lon=slice(15,20), lat=slice(55,48))
                    data2 = data2.sel(lon=slice(15,20), lat=slice(48,43))
    
                    data51 = xr.concat((data5,data1), dim='lat')
                    data512 = xr.concat((data51,data2), dim='lat')
                    data = xr.concat((data4,data512), dim='lon')
                elif zone == 5:
                    data3 = xr.open_dataset(f"/work/bb1478/Darrab/downscaling/models/pr_model/zone3/ens{ens:02d}/{month}/ecmwf_ens{ens:02d}_zone3_pr_{'1993_2014' if set_data=='training' else '2015_2015'}_{month[:2]}_00_downscaled_{set_data}.nc")
                    #data2 = xr.open_dataset(f"/work/bb1478/Darrab/downscaling/models/pr_model/zone2/ens{ens:02d}/{month}/ecmwf_ens{ens:02d}_zone2_pr_{'1993_2014' if set_data=='training' else '2015_2015'}_{month[:2]}_00_downscaled_{set_data}.nc")
                    data2 = xr.open_dataset(f"/work/bb1478/Darrab/bias_correction/bc_medwsa/Pr/zone2/ens{ens:02d}/outputs/bc_medewsa_{'c' if set_data == 'training' else 'v'}al_pr_daily_{'1993-2014' if set_data=='training' else '2015-2015'}_{month[:2]}.nc")
                    
                    data3 = data3.sel(lat=slice(45,30))
                    data2 = data2.sel(lon=slice(9,20), lat=slice(45,30))
        
                    data = xr.concat((data3,data2), dim='lon')
                else: 
                    message = OSError(f'Not known zone {zone}!')
                    print(message)            
                data.to_netcdf(f"./data/zone{zone}/ens{ens:02d}/pr_model/{month}/predict_{set_data}.nc")



if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description='Preprocess PR data for the non-parametric SPEI using R code on xarray data.'
    )
    parser.add_argument('-z', '--zone', type=int, 
                        help='Which zone to preprocess.')
    args = parser.parse_args()
    zone = 5
    if args.zone is not None:
        zone = args.zone
    main(zone)
