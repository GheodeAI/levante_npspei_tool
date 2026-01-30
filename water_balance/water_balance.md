
# Water balance — usage guide

This file documents how to run the water-balance processing pipeline that lives in this folder. The pipeline has two stages:

1. Per-month/per-ensemble processing (driver: `run_water_balance.sh`, which invokes `compute_water_balance.R`).
2. Merge per-ensemble monthly products into final zone-level NetCDFs with `merge_water_balance.sh`.

Files in this folder: SLURM job submission wrapper

- [run_water_balance.sh](https://github.com/cosminmarina/levante_npspei_tool/blob/6299e87e390d33358ef12c6c5236a57ebd9ad28e/water_balance/run_water_balance.sh)

  - A SLURM array driver that prepares the environment and runs `compute_water_balance.R` for one month (each array task covers one month).
  - The script maps SLURM_ARRAY_TASK_ID 1..12 to months:

    - 1 → `01_January`, 2 → `02_February`, …, 12 → `12_December`
  - It calls (example run inside the script):

    ```
    Rscript compute_water_balance.R ${ZONE} ${MONTH} ${OUTPUT_DIR}
    ```
  - Edit SBATCH options in this script (partition, account, time, array range) before submitting for your cluster if required.
  - Submit with:

    ```
    sbatch run_water_balance.sh <zone>
    ```

    Example:
    ```
    sbatch run_water_balance.sh 1
    ```
- [compute_water_balance.R](https://github.com/cosminmarina/levante_npspei_tool/blob/6299e87e390d33358ef12c6c5236a57ebd9ad28e/water_balance/compute_water_balance.R)

  - The R processing script that:
    - Accepts three arguments:
      ```
      Rscript compute_water_balance.R <zone> <month> <output_dir>
      ```
    - Loops ensembles (ens01..ens25) and sets (`training`/`testing`).
    - Reads input NetCDFs for precipitation (PR) and Tmax/Tmin (Tx/Tn), aggregates daily → monthly (PR summed; Tx/Tn mean), calculates PET with Hargreaves (`SPEI::hargreaves()`), computes water balance `wb = P - PET` and writes per-ensemble NetCDFs.
    - Output filename pattern:
      ```
      data/zone<ZONE>/<ensemble>/water_balance_<set>_<month>_<ensemble>.nc
      ```
  - Important variables in the script:
    - `base_path <- "/work/bb1478/Darrab/downscaling/models"` — modify if your downscaled Tx/Tn files live elsewhere.
    - `ensembles <- sprintf("ens%02d", 1:25)` — change if you have a different number of ensembles.
  - The script includes checks for missing/corrupt files and logs progress/warnings into `logs/`.
- [merge_water_balance.sh](https://github.com/cosminmarina/levante_npspei_tool/blob/6299e87e390d33358ef12c6c5236a57ebd9ad28e/water_balance/merge_water_balance.sh)

  - A helper that submits (via an sbatch heredoc) a merge job which uses CDO commands to select months/years and merge per-ensemble monthly files into final products.
  - Usage:
    ```
    ./merge_water_balance.sh <zone>
    ```

    This script submits a SLURM job internally that performs the merge; after submission check the merge job log in `logs/merge_water_zone<ZONE>.log`.
  - If you prefer to submit the merge script directly with `sbatch`, inspect the script first — it spawns its own `sbatch` block. Either:
    - run it directly as shown (recommended), or
    - edit it so it becomes a standalone sbatch script (so you can call `sbatch merge_water_balance.sh <zone>`).

## Environment and dependencies

- SLURM with sbatch available.
- On the compute nodes the following are used/loaded (see `run_water_balance.sh`):
  - R (the script loads `r/4.1.2` in the provided script).
  - netCDF libs (`netcdf-c`), `cdo` is used in merge script.
  - Conda environment `minu_80` was activated in the example — ensure any needed conda env is present or modify the script to use your R environment.
- R packages required by `compute_water_balance.R`:
  - ncdf4
  - SPEI
  - lubridate
    Install in the R environment used by the job (or ensure they are available system-wide).

Input data paths (what the R script expects)

- Precipitation (PR) NetCDFs are expected under:
  ```
  ./data/zone${ZONE}/${ensemble}/${month}/pr_model/predict_${set}.nc
  ```

  (verify the PR file layout in your repository; adjust if your pre-processing places PR files elsewhere)
- Downscaled Tmax/Tmin are read from the `base_path` (hard-coded):
  ```
  /work/bb1478/Darrab/downscaling/models/tx_model/zone${ZONE}/${ensemble}/${month}/ecmwf_${ensemble}_zone${ZONE}_Tx_<years>_<MM>_${set}_00_downscaled_${set}.nc
  ```

  and the analogous `tn_model` path for Tmin.
- If you do not have access to `/work/...` paths or the file naming differs, edit `compute_water_balance.R` to point to your data.

Output structure

- Per-ensemble per-month NetCDF files are written to:

  ```
  data/zone${ZONE}/${ensemble}/water_balance_<set>_<month>_<ensemble>.nc
  ```

  Example:
  ```
  data/zone1/ens01/water_balance_training_01_January_ens01.nc
  ```
- The merge step creates consolidated files (patterns depend on the merge commands inside the merge script). Final expected outputs (typical) are:

  ```
  data/zone{ZONE}/water_balance_training_zone{ZONE}.nc
  data/zone{ZONE}/water_balance_testing_zone{ZONE}.nc
  ```

  Inspect `logs/merge_water_zone{ZONE}.log` to confirm exact output filenames generated by `merge_water_balance.sh`.

## How to run — recommended workflow

1. Submit per-month processing for the chosen zone (array job for 12 months):

   ```
   sbatch run_water_balance.sh <zone>
   ```

   Example:

   ```
   sbatch run_water_balance.sh 1
   ```

   - Each SLURM array task runs one month; monitor with `squeue -u $USER`.
   - Per-array logs are in `logs/water_balance_%a_%A.out`. The R script writes additional logs to `logs/water_balance_zone${ZONE}_${MONTH}.log`.
2. Wait for all array tasks (12 months) to complete for that zone. Confirm per-ensemble files exist:

   ```
   ls data/zone<ZONE>/ens*/water_balance_training_*.nc
   ls data/zone<ZONE>/ens*/water_balance_testing_*.nc
   ```
3. Run the merge helper (this will submit a merge job to SLURM from inside the script):

   ```
   ./merge_water_balance.sh <zone>
   ```

   - The script submits a merge job (via an sbatch heredoc) and writes merge logs to `logs/merge_water_zone${ZONE}.log`.
   - If you prefer a single-level `sbatch` submission, edit `merge_water_balance.sh` to be a standalone sbatch script and then submit with `sbatch merge_water_balance.sh`.

Optional: manual gather + merge (if you want to avoid relying on the internal sbatch in `merge_water_balance.sh`)

- Copy per-ensemble files into a `tmp` directory and run `cdo mergetime` manually:
  ```bash
  ZONE=1
  mkdir -p data/zone${ZONE}/tmp
  cp data/zone${ZONE}/ens*/water_balance_training_*.nc data/zone${ZONE}/tmp/ || true
  cp data/zone${ZONE}/ens*/water_balance_testing_*.nc data/zone${ZONE}/tmp/ || true

  # Merge training
  cdo mergetime data/zone${ZONE}/tmp/water_balance_training_*.nc data/zone${ZONE}/water_balance_training_zone${ZONE}.nc

  # Merge testing
  cdo mergetime data/zone${ZONE}/tmp/water_balance_testing_*.nc data/zone${ZONE}/water_balance_testing_zone${ZONE}.nc
  ```

## Notes & troubleshooting

- Missing input files:
  - `compute_water_balance.R` logs warnings when any input is missing. Check `logs/water_balance_zone{ZONE}_{MONTH}.log`.
  - Verify PR inputs exist at `./data/zone{ZONE}/${ensemble}/${month}/pr_model/predict_{training|testing}.nc`.
  - Verify Tmax/Tmin files exist at the `base_path` referenced in the R script.
- base_path mismatch:
  - If you cannot access `/work/bb1478/...`, change `base_path` at the top of `compute_water_balance.R` to your correct location.
- Corrupt/partial outputs:
  - The R script attempts to remove incomplete output files on error. If you see partial netCDFs, delete them and re-run the affected month/ensemble.
- Merge script behavior:
  - `merge_water_balance.sh` currently wraps merge commands inside a heredoc that is passed to `sbatch`. This means executing `./merge_water_balance.sh <zone>` schedules the merge job. If you instead run `sbatch merge_water_balance.sh <zone>` you will schedule a job that itself calls `sbatch` — usually not desired. If you need `sbatch merge_water_balance.sh <zone>`, edit the script to remove the nested `sbatch` heredoc and expose the merge commands directly as an sbatch script.
- Performance:
  - The driver runs 12 array tasks × up to 25 ensembles × 2 sets; this can be heavy on IO. If you are testing, reduce the ensemble list in `compute_water_balance.R` or run the driver with a reduced array range.
- Logs:
  - Check `logs/water_balance_%a_%A.out` (SLURM driver), per-run log `logs/water_balance_zone{ZONE}_{MONTH}.log`, and `logs/merge_water_zone{ZONE}.log` (merge job).

## References

- `run_water_balance.sh` — SLURM array driver that calls `compute_water_balance.R`

  - https://github.com/cosminmarina/levante_npspei_tool/blob/6299e87e390d33358ef12c6c5236a57ebd9ad28e/water_balance/run_water_balance.sh
- `compute_water_balance.R` — per-ensemble processing

  - https://github.com/cosminmarina/levante_npspei_tool/blob/6299e87e390d33358ef12c6c5236a57ebd9ad28e/water_balance/compute_water_balance.R
- `merge_water_balance.sh` — helper that submits the merge job (uses CDO)

  - https://github.com/cosminmarina/levante_npspei_tool/blob/6299e87e390d33358ef12c6c5236a57ebd9ad28e/water_balance/merge_water_balance.sh
