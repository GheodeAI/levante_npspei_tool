# NP-SPEI Calculation Pipeline for Levante

## Overview

This repository contains a suite of scripts designed to calculate the **Non-Parametric Standardized Precipitation Evapotranspiration Index (NP-SPEI)** using a hybrid Python/R workflow.

### Motivation

Due to memory and time restrictions on the **Levante** HPC system, calculating NP-SPEI for large datasets (all ensembles and zones) simultaneously is not feasible. Specially, due to the time consumption need to process the files. This pipeline solves that problem by:

1. Decomposing NetCDF data into individual grid points.
2. Calculating NP-SPEI for each grid point independently using `rpy2` and the `SPEI` R library.
3. Saving the results as lightweight `.npy` files in a `grid_points/` subdirectory.

This approach allows for massive parallelization via SLURM array jobs.

---

## Prerequisities & Environment

The scripts rely on a specific environment setup on Levante. Ensure your environment matches the modules loaded in the submission scripts:

* **System Modules:**
  * `r/4.1.2-gcc-11.2.0`
  * `gcc/11.2.0-gcc-11.2.0`
  * `pytorch`
* **Conda Environment:** `minu_80`
* **R Libraries:** The scripts point to a custom R library path: `~/R/x86_64-pc-linux-gnu-library/4.1/`. Ensure `SPEI`, `zoo`, `lubridate`, `kde1d`, and `Rmpfr` are installed there.

---

## 🚀 How to Run (Recommended Method)

The primary method for execution is  **`submit_by_zone.sh`** . This script handles the logic for a specific geographical zone, generates the necessary task list for all ensembles (01-25) and months, and submits the SLURM array job.

### Usage

**Bash**

```
./submit_by_zone.sh <zone_number>
```

**Example:**

**Bash**

```
./submit_by_zone.sh 1
```

### What this script does:

1. Accepts a Zone ID (e.g., `1`).
2. Scans `data/zone1/ens{01..25}/` for input NetCDF files (`water_balance_training...` and `water_balance_testing...`).
3. Generates a temporary task file: `tasks_zone1.txt`.
4. Submits a SLURM array job where each task processes one specific file.

---

## Script Descriptions

### Core Logic

#### 1. `np_spei_calculator.py`

The main engine. This Python script:

* Reads the input NetCDF file using `xarray`.
* Connects to R using `rpy2`.
* Iterates through grid points (either all or specific indices via `--grid-index`).
* Calls the R function to compute the index.
* Saves output as `.npy` files in a `grid_points` subdirectory.

#### 2. `np_spei.R`

The scientific kernel. It defines the `np.spei` function and a wrapper `np.spei_py`. It utilizes the `SPEI` and `kde1d` packages to perform the non-parametric estimation.

### Orchestration & Utilities

#### 3. `submit_by_zone.sh` (Recommended)

The main entry point described above. It abstracts away the complexity of managing 25 ensembles per zone.

#### 4. `monitor_jobs.sh`

A utility to track progress. It checks how many output directories and metadata files have been created versus the number of input NetCDF files.

* **Usage:** `./monitor_jobs.sh`

#### 5. `create_tasks.sh` & `submit_spei_array.sh`

*Alternative/Legacy methods.* These scripts generate a massive list of tasks for *all* zones at once. They are useful if you need to run a specific subset of tasks or restart failed jobs globally, rather than zone-by-zone.

#### 6. `run_all_spei.sh`

An all-in-one SLURM submission script that can generate its own task list or run a specific task ID.

---

## Output Structure

The pipeline avoids creating massive NetCDF files during the calculation phase to prevent I/O bottlenecks. Instead, it creates a folder structure like this:

**Plaintext**

```
data/
└── zone1/
    └── ens01/
        ├── spei_training_ens01/       <-- Output Directory
        │   ├── metadata.json          <-- Contains dimensions/coords info
        │   ├── lat.npy                <-- Latitude coordinates
        │   ├── lon.npy                <-- Longitude coordinates
        │   ├── time.npy               <-- Time coordinates
        │   └── grid_points/           <-- THE RESULTS
        │       ├── spei_0_0.npy       <-- Result for lat index 0, lon index 0
        │       ├── spei_0_1.npy
        │       └── ...
```

### Reconstructing the Data

Once the calculations are finished, you can use the `metadata.json` and the files in `grid_points/` to reconstruct a full NetCDF file (see [merge_files](https://github.com/cosminmarina/levante_npspei_tool/tree/7d7b19c5840ecf4650ae93ff9b1d168e032b1dcb/merge_files)).

---

## Configuration

Default parameters are hardcoded in the submission scripts or read from `config/config.json`, but can be overridden via flags in `np_spei_calculator.py`:

* **Scale:** 3 (Standardized over 3 months)
* **Reference Period:** 1981 - 2010
* **Variable Name:** `wb` (Water Balance)

## Troubleshooting

If a job fails:

1. Check the `logs/` directory. The format is `spei_zone{ZONE}_{JOBID}_{TASKID}.log`.
2. Common errors include missing R libraries or corrupted NetCDF inputs.
3. The scripts have built-in skip logic: if `metadata.json` or specific `.npy` grid points exist, they will not be recalculated. You can safely re-submit jobs to finish incomplete runs.
