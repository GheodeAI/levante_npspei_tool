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

base_path <- "/work/bb1478/Darrab/downscaling/models"
sets <- c("training", "testing")
ensembles <- sprintf("ens%02d", 1:25)  # ens01 to ens25

# Function to check if output file exists and is valid
check_output_file <- function(file_path) {
  if (!file.exists(file_path)) {
    return(FALSE)  # File doesn't exist
  }
  
  tryCatch({
    nc <- nc_open(file_path)
    # Check if file has data and correct dimensions
    wb_data <- ncvar_get(nc, "wb")
    nc_close(nc)
    
    # Check if all values are not missing (excluding fill value)
    valid_values <- sum(!is.na(wb_data) & wb_data != -9999)
    return(valid_values > 0)  # Return TRUE if has valid data
  }, error = function(e) {
    cat(sprintf("Error checking file %s: %s\n", file_path, e$message))
    return(FALSE)  # File is corrupted
  })
}

# Function to aggregate daily to monthly
aggregate_to_monthly <- function(data, time_dates, agg_func) {
  # Create year-month groups
  year_mon <- format(time_dates, "%Y-%m")
  unique_months <- unique(year_mon)
  nmonths <- length(unique_months)
  nlon <- ncol(data)
  
  # Create empty matrix for monthly data [time, lon]
  monthly_data <- matrix(NA, nrow = nmonths, ncol = nlon)
  
  # Apply aggregation function to each month
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

# Create logs directory if it doesn't exist
log_dir <- "logs"
if (!dir.exists(log_dir)) {
  dir.create(log_dir, recursive = TRUE)
}

# Log file for this run
log_file <- sprintf("%s/water_balance_zone%s_%s.log", log_dir, zone, month)
cat(sprintf("Processing zone %s, month %s\n", zone, month), file = log_file, append = TRUE)

for (ensemble in ensembles) {
  for (set in sets) {
    # Construct file paths with new structure
    pr_path <- sprintf("./data/zone%s/%s/pr_model/%s/predict_%s.nc",
                      zone, ensemble, month, set)
    
    tx_path <- sprintf("%s/tx_model/zone%s/%s/%s/ecmwf_%s_zone%s_Tx_%s_%s_00_downscaled_%s.nc",
                      base_path, zone, ensemble, month, ensemble, zone,
                      ifelse(set == "training", "1993_2014", "2015_2015"), substr(month, 1, 2), set)
    
    tn_path <- sprintf("%s/tn_model/zone%s/%s/%s/ecmwf_%s_zone%s_Tn_%s_%s_00_downscaled_%s.nc",
                      base_path, zone, ensemble, month, ensemble, zone,
                      ifelse(set == "training", "1993_2014", "2015_2015"), substr(month, 1, 2), set)
    
    # Create output file with ensemble in name
    out_file <- sprintf("%s/%s/water_balance_%s_%s_%s.nc", output_dir, ensemble, set, month, ensemble)
    
    # Check if output file already exists and is valid
    if (check_output_file(out_file)) {
      cat(sprintf("Output file already exists and is valid, skipping: %s\n", out_file))
      cat(sprintf("SKIP: %s/%s/%s\n", ensemble, set, month), file = log_file, append = TRUE)
      next
    }
    
    # Check if input files exist before processing
    missing_files <- c()
    if (!file.exists(pr_path)) missing_files <- c(missing_files, pr_path)
    if (!file.exists(tx_path)) missing_files <- c(missing_files, tx_path)
    if (!file.exists(tn_path)) missing_files <- c(missing_files, tn_path)
    
    if (length(missing_files) > 0) {
      warning_msg <- sprintf("WARNING: Missing input files for %s/%s/%s: %s\n", 
                            ensemble, set, month, paste(missing_files, collapse = ", "))
      cat(warning_msg)
      cat(warning_msg, file = log_file, append = TRUE)
      next
    }
    
    # Create ensemble directory if it doesn't exist
    ensemble_dir <- sprintf("%s/%s", output_dir, ensemble)
    if (!dir.exists(ensemble_dir)) {
      dir.create(ensemble_dir, recursive = TRUE)
    }
    
    # Process with error handling
    tryCatch({
      cat(sprintf("Processing: %s/%s/%s\n", ensemble, set, month))
      cat(sprintf("START: %s/%s/%s\n", ensemble, set, month), file = log_file, append = TRUE)
      
      # Open files
      pr_file <- nc_open(pr_path)
      tx_file <- nc_open(tx_path)
      tn_file <- nc_open(tn_path)
      
      # Get dimensions
      nlon <- pr_file$dim$lon$len
      nlat <- pr_file$dim$lat$len
      ntime_daily <- pr_file$dim$time$len
      
      time_vec <- ncvar_get(pr_file, "time")
      time_units <- ncatt_get(pr_file, "time", "units")$value
      time_cal_att <- tryCatch(
        ncatt_get(pr_file, "time", "calendar"),
        error = function(e) list(hasatt = FALSE)
      )
      time_cal <- if (time_cal_att$hasatt) time_cal_att$value else "proleptic_gregorian"
      
      # Convert to dates
      origin_str <- unlist(strsplit(time_units, " "))[3:4]
      origin_date <- as.POSIXct(paste(origin_str, collapse = " "), tz = "UTC")
      time_dates <- as.Date(origin_date + time_vec * 86400)
      
      # Calculate number of months
      year_mon <- format(time_dates, "%Y-%m")
      unique_months <- unique(year_mon)
      ntime <- length(unique_months)
      
      # Create monthly time vector (15th of each month)
      monthly_dates <- as.Date(paste0(unique_months, "-15"))
      monthly_time <- as.numeric(monthly_dates - as.Date(origin_date))
      
      lon_vec <- ncvar_get(pr_file, "lon")
      lat_vec <- ncvar_get(pr_file, "lat")
      
      fill_pr <- ncatt_get(pr_file, "var", "_FillValue")$value
      fill_tx <- ncatt_get(tx_file, "var", "_FillValue")$value
      fill_tn <- ncatt_get(tn_file, "var", "_FillValue")$value
      
      cat(sprintf("Out file: %s\n", out_file))
      lon_dim <- ncdim_def("lon", "degrees_east", lon_vec)
      lat_dim <- ncdim_def("lat", "degrees_north", lat_vec)
      time_dim <- ncdim_def("time", time_units, monthly_time, calendar = time_cal)
      wb_var <- ncvar_def("wb", "mm", list(lon_dim, lat_dim, time_dim), 
                          missval = -9999, 
                          longname = "Water Balance (P - PET)")
      nc_out <- nc_create(out_file, list(wb_var))
      
      # Process each latitude
      for (j in seq_len(nlat)) {
        cat(sprintf("Processing %s/%s/%s: lat %d/%d\n", month, ensemble, set, j, nlat))
        
        # Read daily data for entire time series
        read_daily_data <- function(nc, fill) {
          data <- ncvar_get(nc, "var", start = c(1, j, 1), count = c(nlon, 1, -1))
          data[data == fill] <- NA
          t(data)  # Convert to [time, lon]
        }
        
        pr_daily <- read_daily_data(pr_file, fill_pr)
        tx_daily <- read_daily_data(tx_file, fill_tx)
        tn_daily <- read_daily_data(tn_file, fill_tn)
        
        # Verify dimensions
        if (nrow(pr_daily) != ntime_daily) {
          stop(sprintf("Dimension mismatch: pr_daily has %d rows, expected %d", 
                       nrow(pr_daily), ntime_daily))
        }
        
        # Aggregate to monthly
        pr_monthly <- aggregate_to_monthly(pr_daily, time_dates, sum)
        tx_monthly <- aggregate_to_monthly(tx_daily, time_dates, mean)
        tn_monthly <- aggregate_to_monthly(tn_daily, time_dates, mean)
        
        # Compute PET using hargreaves
        lat_j <- lat_vec[j]
        pet_monthly <- matrix(NA, nrow = ntime, ncol = nlon)
        
        # Process in chunks
        chunk_size <- min(1000, nlon)
        for (start_idx in seq(1, nlon, by = chunk_size)) {
          end_idx <- min(start_idx + chunk_size - 1, nlon)
          current_chunk <- seq(start_idx, end_idx)
          num_points <- length(current_chunk)
          
          # Create latitude vector for the chunk
          lat_vec_chunk <- rep(lat_j, num_points)
          
          pet_chunk <- hargreaves(
            Tmin = tn_monthly[, current_chunk, drop = FALSE],
            Tmax = tx_monthly[, current_chunk, drop = FALSE],
            lat = lat_vec_chunk,
            na.rm = TRUE,
            verbose = FALSE
          )
          
          pet_monthly[, current_chunk] <- pet_chunk
        }
        
        # Compute water balance
        wb_block <- pr_monthly - pet_monthly
        wb_block[is.na(wb_block)] <- -9999
        
        # Write to output
        wb_out <- array(NA, dim = c(nlon, 1, ntime))
        for (i in 1:ntime) {
          wb_out[, 1, i] <- wb_block[i, ]
        }
        ncvar_put(nc_out, "wb", wb_out, start = c(1, j, 1), count = c(nlon, 1, ntime))
      }
      
      nc_close(pr_file)
      nc_close(tx_file)
      nc_close(tn_file)
      nc_close(nc_out)
      cat(sprintf("SUCCESS: Created %s\n", out_file))
      cat(sprintf("SUCCESS: %s/%s/%s\n", ensemble, set, month), file = log_file, append = TRUE)
      
    }, error = function(e) {
      error_msg <- sprintf("ERROR in %s/%s/%s: %s\n", ensemble, set, month, e$message)
      cat(error_msg)
      cat(error_msg, file = log_file, append = TRUE)
      
      # Clean up partially created files
      if (file.exists(out_file)) {
        file.remove(out_file)
        cat(sprintf("Removed incomplete file: %s\n", out_file))
      }
    })
  }
}

cat(sprintf("Completed processing zone %s, month %s\n", zone, month), file = log_file, append = TRUE)