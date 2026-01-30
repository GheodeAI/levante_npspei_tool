# levante_npspei_tool

This repository contains a complete pipeline for calculating the **Non-Parametric Standardized Precipitation Evapotranspiration Index (NP-SPEI)** on the Levante HPC system.

The workflow is designed to handle large-scale climate data by breaking down the process into four distinct modular steps: preprocessing data, calculating water balance, computing the index in parallel, and reconstructing the final output.

## Workflow Overview

### Step 1: Preprocess

**Goal:** Harmonize Precipitation (PR) data zoning.

The raw precipitation data is provided in a 6-zone layout, while Temperature (TN/TX) and downstream models use a 5-zone layout. This step stitches and slices the PR data to match the required 5-zone format.

* **Key Script:** `preprocess_pr_model.py`
* **Input:** Raw PR NetCDF files (6 zones).
* **Output:** Preprocessed PR NetCDF files organized by ensemble and month (5 zones).

[📂 **Go to Preprocess Tutorial**](https://github.com/cosminmarina/levante_npspei_tool/blob/da2074495753ca3b3a169ce7465939674e2c388a/preprocess/preprocess.md)

---

### Step 2: Water Balance

**Goal:** Compute the monthly Water Balance ($P - PET$).

Using the preprocessed precipitation and downscaled temperature data (Tmax/Tmin), this step calculates the Potential Evapotranspiration (PET) using the Hargreaves method and derives the water balance.

* **Key Scripts:** `run_water_balance.sh`, `compute_water_balance.R`, `merge_water_balance.sh`
* **Input:** Preprocessed PR data (from Step 1) and Downscaled TN/TX.
* **Output:** Monthly Water Balance NetCDF files per ensemble.

[📂 **Go to Water Balance Tutorial**](https://github.com/cosminmarina/levante_npspei_tool/blob/da2074495753ca3b3a169ce7465939674e2c388a/water_balance/water_balance.md)

---

### Step 3: NP-SPEI Calculation

**Goal:** Compute NP-SPEI for individual grid points.

To bypass memory restrictions on the HPC, the Water Balance NetCDF files are decomposed into individual grid points. A hybrid Python/R workflow calculates the Non-Parametric SPEI for each point in parallel using SLURM array jobs.

* **Key Scripts:** `submit_by_zone.sh`, `np_spei_calculator.py`
* **Input:** Water Balance NetCDFs (from Step 2).
* **Output:** Thousands of lightweight `.npy` files (one per grid point) in a `grid_points/` subdirectory.

[📂 **Go to NP-SPEI Tutorial**](https://github.com/cosminmarina/levante_npspei_tool/blob/da2074495753ca3b3a169ce7465939674e2c388a/npspei/npspei.md)

---

### Step 4: Merge Files

**Goal:** Reconstruct the final global NetCDF.

The final step gathers the thousands of individual grid point results produced in Step 3 and reconstructs them into a single, coherent NetCDF file for analysis. It includes checkpointing to resume interrupted merges safely.

* **Key Script:** `create_netcdf.py`
* **Input:** Directory of `.npy` grid point files (from Step 3).
* **Output:** Final NP-SPEI NetCDF file (e.g., `npspei_1993_2014_ens01.nc`).

[📂 **Go to Merge Files Tutorial**](https://github.com/cosminmarina/levante_npspei_tool/blob/da2074495753ca3b3a169ce7465939674e2c388a/merge_files/merge_files.md)

## Prerequisites

To run these tools on Levante, ensure you have the following environment modules and libraries available (details in individual folder READMEs):

* **System Modules:** `r/4.1.2`, `cdo`, `pytorch`
* **Conda or PythonEnv:**  environment wiht the needed packages.
* **R Packages:** `SPEI`, `kde1d`, `zoo`, `lubridate`, `Rmpfr`
