# Non-Parametric SPEI Calculation (Fast Runner) README

## Motivation

Calculating the Non-Parametric Standardized Precipitation Evapotranspiration Index (NP-SPEI) is computationally intensive, especially for high-resolution gridded data. Standard R implementations often struggle with memory management when processing large NetCDF files.

This toolset provides a **hybrid optimized workflow**:

1. **Python** handles the heavy I/O, memory mapping, and parallelization.
2. **R** is called efficiently via `rpy2` to perform the statistical calculations (`kde1d`) on chunks of data.

This approach minimizes memory overhead and allows for robust failure recovery via checkpointing.

## Files in this folder

* **[submit_by_zone.sh](https://www.google.com/search?q=submit_by_zone.sh)**
* The main entry point for SLURM cluster execution.
* **Usage:** `./submit_by_zone.sh <zone_number>`
* **Function:**
1. Scans the directory structure for Water Balance NetCDF files (`water_balance_*.nc`).
2. Generates a task list (`tasks_zoneX.txt`) mapping inputs to outputs.
3. Submits a SLURM array job to process these files in parallel.




* **[spei_fast_runner.py](https://www.google.com/search?q=spei_fast_runner.py)**
* The Python driver script.
* **Function:**
* Reads the input NetCDF using `xarray`.
* Creates a memory-mapped file on disk to store results (avoiding RAM overflows).
* Batches pixels and sends valid (non-ocean) time series to R.
* Saves the final result as a NetCDF file.


* **Key Arguments:** `--input`, `--output`, `--r-script`, `--scale`, `--ref-start`, `--ref-end`.


* **[np_spei_optimized.R](https://www.google.com/search?q=np_spei_optimized.R)**
* The statistical core.
* **Function:** Contains the `np.spei` function and a helper `np.spei_batch` function.
* It utilizes the `kde1d` package for kernel density estimation and `zoo` for time-series management.



## Environment and Dependencies

The scripts rely on a specific environment setup (as seen in the SLURM directives):

### System Modules

* `r/4.1.2-gcc-11.2.0` (or compatible R version)
* `gcc/11.2.0`
* `pytorch` (often loaded for Python dependencies)

### Python Environment (`minu_80`)

Must include:

* `rpy2` (crucial for Python-to-R communication)
* `xarray`, `numpy`, `pandas`
* `tqdm` (for progress bars)

### R Packages

The R environment must have the following packages installed:

* `zoo`
* `lubridate`
* `kde1d`
* `SPEI`
* `Rmpfr`

## Input Data Paths

The workflow expects a specific directory structure. The `submit_by_zone.sh` script looks for files in:

```text
data/zone{ZONE}/ens{ENSEMBLE}/water_balance_{training|testing}_ens{ENSEMBLE}.nc

```

* **Variable Name:** The Python script defaults to looking for a variable named `wb` (Water Balance) inside these NetCDFs.
* **Dimensions:** The scripts expect standard `(time, lat, lon)` dimensions.

## Output Structure

For each input file processed, the script generates a corresponding SPEI file in the same directory:

```text
data/zone{ZONE}/ens{ENSEMBLE}/spei_{training|testing}_ens{ENSEMBLE}.nc

```

### Temporary Files

During execution, `spei_fast_runner.py` creates a temporary directory (e.g., `spei_output.nc_temp_data`) to store memory-mapped arrays and checkpoint metadata. **This is automatically cleaned up** upon successful completion.

## How to Run

### 1. Basic Usage (Cluster)

To process a specific zone (e.g., Zone 2), run the submission script:

```bash
./submit_by_zone.sh 2

```

This will:

1. Generate `tasks_zone2.txt`.
2. Submit a SLURM array job.
3. Output logs to `logs/spei_zone2_JOBID_TASKID.log`.

### 2. Manual/Interactive Usage

If you need to debug or run a single file interactively without SLURM:

```bash
# 1. Load your environment
module load r/4.1.2-gcc-11.2.0
conda activate minu_80

# 2. Run the python runner directly
python spei_fast_runner.py \
    --input "data/zone2/ens14/water_balance_training_ens14.nc" \
    --output "test_spei_output.nc" \
    --r-script "np_spei_optimized.R" \
    --scale 3 \
    --ref-start 1981 \
    --ref-end 2010

```

## Configuration & Customization

### Changing the Time Scale

By default, the script calculates **SPEI-3** (3-month scale). To change this, edit `submit_by_zone.sh`:

```bash
# Inside submit_by_zone.sh
python spei_fast_runner.py \
    ...
    --scale 6 \   # Change to 6 for SPEI-6
    ...

```

### Adjusting Ensembles

Currently, `submit_by_zone.sh` is configured to run a specific set of ensembles (e.g., `seq 14 14`). To run all ensembles, update the loop:

```bash
# Change:
for ensemble in $(seq -f "%02g" 14 14); do
# To:
for ensemble in $(seq -f "%02g" 01 25); do

```

## Troubleshooting

* **"R script not found"**: Ensure `np_spei_optimized.R` is in the same directory as the Python script, or provide the absolute path in the `--r-script` argument.
* **Memory Errors**:
* The Python script uses `np.memmap` to keep RAM usage low. However, if R crashes, try reducing the `batch_size` in `spei_fast_runner.py` (default is 500 pixels per batch).


* **Permissions**: Ensure you have write access to the `data/zoneX/` directories, as the script attempts to write the output NetCDF files there.
* **Checkpointing**: If a job fails (e.g., timeout), simply resubmit. The script detects `_temp_data` folders and resumes from the last saved index.