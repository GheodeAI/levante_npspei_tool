#!/usr/bin/env Rscript
library(ncdf4)
library(SPEI)
library(lubridate)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3) {
  stop("Usage: Rscript compute_water_balance.R <zone> <month> <output_dir>\n")
}
zone <- args[1]
month <- args[2]
output_dir <- args[3]

base_path <- "/work/bb1478/Darrab/bias_correction/bc_medwsa"
sets <- c("training", "testing")
ensembles <- sprintf("ens%02d", 1:26)

# --- CONSTANTS FOR OUTPUT ---
MISSING_VAL <- -9999.0   # fill value (float)

# --- HELPER FUNCTIONS ---

# Function to detect where to resume
get_resume_index <- function(file_path, nlat, nlon) {
  if (!file.exists(file_path)) return(1)

  nc <- nc_open(file_path)
  last_lat <- 1

  cat(sprintf("Checking resume index for %s...\n", basename(file_path)))

  for (j in 1:nlat) {
    row_data <- ncvar_get(nc, "wb", start = c(1, j, 1), count = c(nlon, 1, 1))
    if (all(row_data == MISSING_VAL, na.rm = TRUE)) {
      last_lat <- j
      break
    }
    if (j == nlat) last_lat <- nlat + 1
  }

  nc_close(nc)
  return(last_lat)
}

aggregate_to_monthly <- function(data, time_dates, agg_func) {
  year_mon <- format(time_dates, "%Y-%m")
  unique_months <- unique(year_mon)
  nmonths <- length(unique_months)
  nlon <- ncol(data)
  monthly_data <- matrix(NA, nrow = nmonths, ncol = nlon)

  for (i in seq_along(unique_months)) {
    mon <- unique_months[i]
    idx <- which(year_mon == mon)
    if (length(idx) > 0) {
      if (identical(agg_func, sum)) {
        monthly_data[i, ] <- colSums(data[idx, , drop = FALSE], na.rm = TRUE)
      } else if (identical(agg_func, mean)) {
        monthly_data[i, ] <- colMeans(data[idx, , drop = FALSE], na.rm = TRUE)
      }
    }
  }
  return(monthly_data)
}

# --- MAIN PROCESSING ---

log_dir <- "logs"
if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
log_file <- sprintf("%s/water_balance_zone%s_%s.log", log_dir, zone, month)

for (ensemble in ensembles) {
  for (set in sets) {
    # 1. Define Paths
    pr_path <- sprintf("./data/zone%s/%s/pr_model/%s/predict_%s.nc", zone, ensemble, month, set)
    tx_path <- sprintf("%s/Tx/zone%s/%s/outputs/bc_medewsa_%sal_tx_daily_%s_%s.nc",
                       base_path, zone, ensemble, ifelse(set == "training", "c", "v"),
                       ifelse(set == "training", "1993-2014", "2015-2015"), substr(month, 1, 2))
    tn_path <- sprintf("%s/Tn/zone%s/%s/outputs/bc_medewsa_%sal_tn_daily_%s_%s.nc",
                       base_path, zone, ensemble, ifelse(set == "training", "c", "v"),
                       ifelse(set == "training", "1993-2014", "2015-2015"), substr(month, 1, 2))

    out_file <- sprintf("%s/%s/water_balance_%s_%s_%s.nc", output_dir, ensemble, set, month, ensemble)
    ensemble_dir <- dirname(out_file)
    if (!dir.exists(ensemble_dir)) dir.create(ensemble_dir, recursive = TRUE)

    # 2. Check Input Files
    if (!all(file.exists(pr_path, tx_path, tn_path))) {
      cat(sprintf("SKIP: Missing inputs for %s\n", out_file), file = log_file, append = TRUE)
      next
    }

    tryCatch({
      # 3. Open Input Files to get Setup Info
      pr_file <- nc_open(pr_path)
      nlon <- pr_file$dim$lon$len
      nlat <- pr_file$dim$lat$len
      ntime_daily <- pr_file$dim$time$len

      # Determine Resume Point
      start_lat <- get_resume_index(out_file, nlat, nlon)

      if (start_lat > nlat) {
        cat(sprintf("ALREADY DONE: %s\n", out_file))
        nc_close(pr_file)
        next
      }

      # 4. Prepare Output File (Create or Open for Append)
      if (start_lat == 1) {
        # Create NEW file
        cat(sprintf("Creating NEW file: %s\n", out_file))

        # Setup dimensions
        time_vec <- ncvar_get(pr_file, "time")
        time_units <- ncatt_get(pr_file, "time", "units")$value
        time_cal_att <- tryCatch(ncatt_get(pr_file, "time", "calendar"), error = function(e) list(hasatt=FALSE))
        time_cal <- if(time_cal_att$hasatt) time_cal_att$value else "proleptic_gregorian"

        origin_str <- unlist(strsplit(time_units, " "))[3:4]
        origin_date <- as.POSIXct(paste(origin_str, collapse = " "), tz = "UTC")
        time_dates <- as.Date(origin_date + time_vec * 86400)

        year_mon <- format(time_dates, "%Y-%m")
        unique_months <- unique(year_mon)
        ntime <- length(unique_months)

        monthly_dates <- as.Date(paste0(unique_months, "-15"))
        monthly_time <- as.numeric(monthly_dates - as.Date(origin_date))

        lon_vec <- ncvar_get(pr_file, "lon")
        lat_vec <- ncvar_get(pr_file, "lat")

        lon_dim <- ncdim_def("lon", "degrees_east", lon_vec)
        lat_dim <- ncdim_def("lat", "degrees_north", lat_vec)
        time_dim <- ncdim_def("time", time_units, monthly_time, calendar = time_cal)

        # Define variable as 32-bit float, rounded to 2 decimal places on write
        wb_var <- ncvar_def("wb", "mm", list(lon_dim, lat_dim, time_dim),
                            missval = MISSING_VAL, longname = "Water Balance (P - PET)",
                            prec = "float", compression = 5)

        nc_out <- nc_create(out_file, list(wb_var))

        # Pre-fill with missing value
        ncvar_put(nc_out, "wb", array(MISSING_VAL, dim = c(nlon, nlat, ntime)))
        nc_sync(nc_out)

        # Retrieve lat_vec for later use
        lat_vec <- ncvar_get(pr_file, "lat")
      } else {
        # RESUME existing file
        cat(sprintf("RESUMING %s from lat %d\n", out_file, start_lat))

        # Reconstruct date/time info for aggregation
        time_vec <- ncvar_get(pr_file, "time")
        time_units <- ncatt_get(pr_file, "time", "units")$value
        origin_str <- unlist(strsplit(time_units, " "))[3:4]
        origin_date <- as.POSIXct(paste(origin_str, collapse = " "), tz = "UTC")
        time_dates <- as.Date(origin_date + time_vec * 86400)

        lat_vec <- ncvar_get(pr_file, "lat")

        # Open in WRITE mode
        nc_out <- nc_open(out_file, write = TRUE)
        ntime <- nc_out$dim$time$len
      }

      # Open other input files
      tx_file <- nc_open(tx_path)
      tn_file <- nc_open(tn_path)

      fill_pr <- ncatt_get(pr_file, "pr", "_FillValue")$value
      fill_tx <- ncatt_get(tx_file, "tx", "_FillValue")$value
      fill_tn <- ncatt_get(tn_file, "tn", "_FillValue")$value

      # 5. Process Loop
      for (j in start_lat:nlat) {
        if (j %% 10 == 0) cat(sprintf("Processing %s/%s: lat %d/%d\n", ensemble, month, j, nlat))

        # Helper to read one row of daily data
        read_daily_row <- function(nc, fill, var_name) {
          data <- ncvar_get(nc, var_name, start = c(1, j, 1), count = c(nlon, 1, -1))
          data[data == fill] <- NA
          return(t(data))   # [time, lon]
        }

        pr_daily <- read_daily_row(pr_file, fill_pr, "pr")
        tx_daily <- read_daily_row(tx_file, fill_tx, "tx")
        tn_daily <- read_daily_row(tn_file, fill_tn, "tn")

        pr_monthly <- aggregate_to_monthly(pr_daily, time_dates, sum)
        tx_monthly <- aggregate_to_monthly(tx_daily, time_dates, mean)
        tn_monthly <- aggregate_to_monthly(tn_daily, time_dates, mean)

        # Compute PET
        lat_j <- lat_vec[j]
        pet_monthly <- matrix(NA, nrow = ntime, ncol = nlon)

        for (i in 1:nlon) {
          tmax_vec <- as.numeric(tx_monthly[, i])
          tmin_vec <- as.numeric(tn_monthly[, i])

          if (!all(is.na(tmax_vec)) && !all(is.na(tmin_vec))) {
            pet_val <- hargreaves(Tmin = tmin_vec, Tmax = tmax_vec, lat = lat_j, na.rm = TRUE, verbose = FALSE)
            pet_monthly[, i] <- as.numeric(pet_val)
          }
        }

        # Water Balance (real values, rounded to 2 decimal places)
        wb_block <- round(pr_monthly - pet_monthly, 2)
        wb_block[is.na(wb_block)] <- MISSING_VAL

        # Reshape for writing: (lon, 1, time)
        wb_out <- array(MISSING_VAL, dim = c(nlon, 1, ntime))
        for (t in 1:ntime) {
          wb_out[, 1, t] <- wb_block[t, ]
        }

        ncvar_put(nc_out, "wb", wb_out, start = c(1, j, 1), count = c(nlon, 1, ntime))

        if (j %% 50 == 0) nc_sync(nc_out)
      }

      # Cleanup
      nc_close(pr_file)
      nc_close(tx_file)
      nc_close(tn_file)
      nc_close(nc_out)

      cat(sprintf("COMPLETED: %s\n", out_file))
      cat(sprintf("SUCCESS: %s/%s/%s\n", ensemble, set, month), file = log_file, append = TRUE)

    }, error = function(e) {
      cat(sprintf("ERROR in %s: %s\n", out_file, e$message))
      cat(sprintf("ERROR: %s/%s/%s - %s\n", ensemble, set, month, e$message), file = log_file, append = TRUE)
    })
  }
}
