# Merge Files — Reconstruct NP-SPEI NetCDF from per-grid-point outputs

Purpose
-------

Levante resource restrictions prevented calculating NP‑SPEI for the entire domain in a single run. Instead, NP‑SPEI is computed per grid point using the per-grid-point process in the `npspei` folder:

- [npspei](https://github.com/cosminmarina/levante_npspei_tool/tree/dcbb1bda8d3b6c2b0e88aeea90ab6607fb3841ae/npspei)

Each grid point calculation writes a single NumPy file (named `spei_<i>_<j>.npy`) into a `grid_points` subfolder. The scripts in this `merge_files` folder postprocess those per-grid-point results and reconstruct a single NetCDF file containing NP‑SPEI for all grid points.

This document explains what each script does, prerequisites, how to run them (SLURM and locally), checkpointing behavior, and troubleshooting tips.

Files covered
-------------

- submit_recon.sh — SLURM submission wrapper that computes ensemble/type mapping and invokes create_netcdf.py.
- create_netcdf.py — Reconstructs the final NetCDF from per-grid-point .npy files and supports checkpoints.

(Full source references are provided below.)

Motivation and data layout
--------------------------

- Per-grid computations create files:
  - `grid_points/spei_<i>_<j>.npy` — 1D NumPy array of SPEI values for the timeseries of that grid point.
- Required shared arrays (in the same `output_dir`) used to reassemble:
  - `time.npy` — 1D array of time values (matching length for every grid point file).
  - `lat.npy`, `lon.npy` — 1D arrays of latitude and longitude coordinates.
  - `metadata.json` — JSON with metadata keys used by the reconstructor (see `Metadata` below).
- Final output:
  - A single NetCDF (e.g., `npspei_1993_2014_ens01.nc`) containing variable `spei(time, lat, lon)`.

Run order
---------

1. submit_recon.sh
   - This is the user-facing SLURM array job script. It sets environment modules/conda, computes which ensemble (`ENS`) and `TYPE` (training/testing) correspond to the array index, builds the output directory and file names, checks whether processing is already complete, and calls `create_netcdf.py`.
2. create_netcdf.py
   - Scans the `grid_points` directory for `spei_<i>_<j>.npy` files, loads `time.npy`, `lat.npy`, `lon.npy`, and `metadata.json`, and reconstructs a 3D array `spei(time, lat, lon)`.
   - Supports checkpointing: periodically saves a `.temp` NetCDF and renames it to the target file so the process can be resumed without reprocessing grid points that already have non-NaN values.

Detailed behavior (create_netcdf.py)
------------------------------------

- Inputs (arguments)

  - `--output-dir` (required): directory containing `grid_points/`, `time.npy`, `lat.npy`, `lon.npy`, and `metadata.json`.
  - `--output-file` (optional): target NetCDF filename (default `spei_output.nc`).
- Expected files inside `output_dir`:

  - `grid_points/` — contains `spei_#_#.npy` files for each grid point
  - `time.npy`, `lat.npy`, `lon.npy` — coordinate arrays
  - `metadata.json` — must include keys:
    - `scale` — scale of the SPEI (copied into output attributes)
    - `ref_start`, `ref_end` — reference period used (copied into attributes)
    - `input_file` — original input name (copied into attributes)
- Checkpointing:

  - If output NetCDF already exists, the script attempts to open it and detect which grid points already contain non-NaN data (i.e., already processed). Those grid points are skipped.
  - As it processes new grid point files, it periodically writes a temporary NetCDF (`<output_file>.temp`) and atomically replaces the main file. This prevents re-doing already assembled grid points after interruptions.
  - The checkpoint interval is dynamic: `min(100, max(10, total_files // 20))`.
- Data validation:

  - For each `spei_<i>_<j>.npy` file the script verifies the 1D length equals the `time` length. Mismatches are reported and the file is recorded as failed.
- Final NetCDF:

  - Contains data variable `spei(time, lat, lon)` and attributes:
    - `description: "Non-parametric SPEI"`
    - `scale: <from metadata.json>`
    - `reference_period: "<ref_start>-<ref_end>"`
    - `source_file: <input_file>`
    - `processing_complete: "True"`
    - `processed_grid_points: "<processed>/<total>"`

submit_recon.sh — SLURM wrapper (behaviour)
--------------------------------------------

- Uses SBATCH array indices to split jobs:
  - Array indices `1-25` → `training` sets with `YEARS="1993_2014"`
  - Array indices `26-50` → `testing` sets with `YEARS="2015_2015"`
- Builds:
  - `OUTPUT_DIR="data/zone5/ens${ENS}/spei_${TYPE}_ens${ENS}"`
  - `OUTPUT_FILE="npspei_${YEARS}_ens${ENS}.nc"`
- Before calling Python, checks if the target NetCDF already exists and has `processing_complete.*True` in its header (via `ncdump -h`). If so, it skips processing.
- Loads Conda and modules as needed (`pytorch` module and `conda activate minu_80` in the current script—adjust to your environment).

How to run
----------

- On the SLURM cluster:

  - Submit the array job as intended for the script (the script already contains SBATCH header lines):
    sbatch submit_recon.sh
- Locally or for debugging:

  - Activate the same Python environment (ensure `numpy`, `xarray` are available).
  - Run create_netcdf.py directly:
    ```bash
    python create_netcdf.py --output-dir path/to/output_dir --output-file npspei_1993_2014_ens01.nc
    ```
  - If you re-run against the same output directory, the script will resume where it left off (using the checkpoint logic).

Dependencies
------------

- Python packages:
  - numpy
  - xarray
- System:
  - netCDF tools (for `ncdump` check in the SLURM wrapper), optional but used by submit_recon.sh
- Conda environment: the script expects `minu_80` in submit_recon.sh (adjust to your environment).

Troubleshooting & tips
----------------------

- Missing or malformed metadata.json:
  - create_netcdf.py expects keys `scale`, `ref_start`, `ref_end`, and `input_file`. Add them if missing.
- Time/shape mismatch warnings:
  - If you see "Warning: Dimension mismatch", make sure the grid point `.npy` has the same number of timesteps as `time.npy`.
- Re-running:
  - Safe to re-run; the script detects already processed grid points from the NetCDF and will skip them.
- Partial failures:
  - The script prints `failed_files` at the end. You can inspect those `.npy` files directly for corruption or mismatched length.
- Adjusting checkpoint frequency:
  - The script chooses a dynamic checkpoint interval. If you want more frequent updates, edit the `checkpoint_interval` logic inside `create_netcdf.py`.

Example directory tree (expected)
---------------------------------

output_dir/

- metadata.json
- time.npy
- lat.npy
- lon.npy
- grid_points/
  - spei_0_0.npy
  - spei_0_1.npy
  - ...
- npspei_1993_2014_ens01.nc  (output / checkpointed file)
