# Description: Hourly to Annual ERA5 Aggregation
#
# Overview: Code to conduct temporal aggregation from hourly ERA5-Land
# rasters to daily minimum, mean, and maximum temperatures. From the
# daily variables, we derive annual averages for the minimum, mean, and 
# maximum temperature.
#
# Authors: Zach Popp (zpopp@bu.edu), Allison James (alliej@bu.edu)
# Date Created: 08/20/2026
# Version Number: v1
#
# Instructions:
#
# Load required packages
#
library("terra")
library("lubridate")
library("lutz")
library("sf")

# Check package version numbers
#
if (packageVersion("ecmwfr") < "1.5.0"   | packageVersion("sf") < "1.0.16" ) {
  cat("WARNING: packages are outdated and may result in errors.") }

################### User-Define Parameters #####################################
# Set directory. Establishing this at the start of the script is useful in case
# future adjustments are made to the path. 
#
ecmw_dir <- "<INSERT_PATH_FOR_DOWNLOADS_HERE>"   # Pathway of the directory where your ERA5 rasters will be stored after download.
# Note that this code is setup assuming there is a nested 'hourly' subfolder
# in the ecmw_dir. This script also assumes there are 'daily' and 'annual' 
# subfolders in the same directory. If you are not using this filenaming 
# convention, adjust the script where ecmw_dir is referenced!
# ** If you change this, be sure to keep the final forward slash **
# "Input data" is any data set that is *not* the final, analytical dataset.

################### Data Ingestion and Time Zone Extraction ####################

# Note that we add hourly to indicate this is the files as downloaded from 
# the Copernicus Climate Data Store
#
era_files <- list.files(paste0(ecmw_dir, "/hourly/"), 
                        pattern=paste0('.*.nc'), full.names = F)

# Load one raster
#
era_single <- rast(paste0(ecmw_dir, "/hourly/", era_files[1]))

# Time zone setup
# The SpatRaster as downloaded from Copernicus will include hourly data based on
# the UTC time zone. When we calculate our daily summary statistics in the loop
# below, we want to make sure we are calculating statistics from midnight to
# midnight, using the local time zone. Specify the time zone relevant for your 
# data below. Note: If you are attempting to aggregate across multiple distinct
# time zones, additional processing is necessary. 
#
# First get points of all grid cells
#
points_data <- terra::as.points(era_single[[1]])

# The use the tz_lookup functon to append a time zone to each point
#
points_data$tz <- tz_lookup(st_as_sf(points_data), method = "accurate")

# Get a list of all unique time zones
#
all_tz <- unique(points_data$tz)

################### Temporal Aggregation Loop ##################################

# To get daily and annual maxima based on the local time zone, we are going to 
# use a series of for loops. These loops included nested processing by:
#       year -->
#           metric -->
#               timezone -->
#
# We read in all ERA5 data (across metrics) for a given year, and then create
# separate raster stacks for each variable (based on the raster stack name).
# For this tutorial, we are processing d2m (dew point temperature) and t2m
# (2-meter air temperature). We set up a list that has each of the raster stacks
# separated, and then proceed with temporal aggregation by time zone.
# For each time zone, we will append the time zone corrected (data is downloaded
# in UTC) time to every hour of ERA5 data. We will then set up a vector list
# that will flag each raster layer with its corresponding date based on local
# time. We next estimate the minimum, mean, and maximum for each metric across
# the local 24-hour day. We combine these rasters across time zones (as needed)
# so we have a three sets (daily min, mean, max) of rasters for a given 
# metric and year. We write the daily raster stacks to a file, and then 
# move ahead to processing annual aggregate mean metrics for each year. These
# are then stored as separate raster files.
#
# Set year to process
#
years_to_agg <- c(2023:2024)

for (year in c(years_to_agg)) {
  
  cat("Now processing ", year, "\n")
  
  # Subset to year from all files 
  #
  era_files_yr <- era_files[grepl(year, era_files) | grepl(year + 1, era_files) ]
  
  # Stack all of the daily files by year
  #
  era_files_yr <- paste0(ecmw_dir, "hourly/", era_files_yr)
  era_stack <- rast(era_files_yr)
  
  # Align times (first in UTZ)
  # Note, if time(terra) is NA, then use the commented out code below
  # to add a time dimension to the raster. This will be the case for terra
  # version 1.8 or prior. You can use packageVersion("terra") to check.
  #
  # terra::time(era_stack) <- as_datetime(as.numeric(sub(".*=", "", names(era_stack))))
  #
  # Otherwise proceed from here
  #
  terra::time(era_stack) <- as.POSIXct(terra::time(era_stack), 
                format = "%Y-%m-%d %Z", 
                tz = "UTC")
      
  # Subset stack to exclude the times that run past specified year due to 
  # time zone adjustment, and to exclude the previous year that was read in 
  # for time zone adjustment
  #
  era_stack <- subset(era_stack, time(era_stack) < date(paste0(year + 1, "-01-01")) &
                        time(era_stack) >= date(paste0(year, "-01-01")))
  
  # Our ERA stack includes two variables (2m dew point temperature,
  # skin temperaturee). Create subsets to perform
  # daily aggregation on
  #
  dewpoint_names <- names(era_stack)[grepl("d2m", names(era_stack))]
  temp2m_names <- names(era_stack)[grepl("t2m", names(era_stack))]
  
  # Subset raster to each measure and convert Kelvin to Celsius
  #
  era_stack_d2m <- subset(era_stack, names(era_stack) %in% dewpoint_names) - 273.15
  era_stack_t2m <- subset(era_stack, names(era_stack) %in% temp2m_names) - 273.15
  
  # Confirm all layers are same length
  #
  if (nlyr(era_stack_d2m) == nlyr(era_stack_t2m)) {
    layer_n <- nlyr(era_stack_d2m)
    cat("Same number of layers in all stacks\n")
  } else {
    cat("Different number of layers, assess whether timing is consistent\n")
    break
  }
  
  # Set list of rasters. We will do the same processing of daily minimum, mean,
  # and maximum for the different variables we queried through ERA5, so we set
  # the lasters in a list and conduct the processing as below
  #
  list_rasters <- list(era_stack_d2m, era_stack_t2m)
  
  for (i in 1:length(list_rasters)) {
    
    # Tracker for viewing progress
    #
    cat("Now processing raster ", i, "\n")
    
    # Get raster for variable
    #
    era_var <- list_rasters[[i]]
    
    # Get name of variable
    #
    varname <- unique(substr(names(era_var), 1, 3))
    
    cat(varname, "\n")
    
    # For each output (daily min/max/mean)
    # Set up empty list of rasts
    # We will add to this the timezone specific rasters, then we will merge
    #
    min_rasts <- list()
    mean_rasts <- list()
    max_rasts <- list()
    
    # Filter through the unique time zones that are included. We are doing the 
    # daily aggregation here.
    #
    for (timezone in c(all_tz)) {
      
      ##################### Time Zone Conversion ###################################
      
      # Set time zone specific raster
      #
      era_rast_tz <- mask(era_var, points_data[points_data$tz == timezone, ])
      
      # Align times (first in UTZ)
      # Note, if time(terra) is NA, then use the commented out code below
      # to add a time dimension to the raster. This will be the case for terra
      # version 1.8 or prior
      #
      # terra::time(era_rast_tz) <- as_datetime(as.numeric(sub(".*=", "", names(era_rast_tz))))
      #
      # Otherwise proceed from here
      #
      terra::time(era_rast_tz) <- as.POSIXct(terra::time(era_rast_tz), 
                                             format = "%Y-%m-%d %Z", 
                                             tz = "UTC")
      
      # Reset times to align with specified time zone
      #
      terra::time(era_rast_tz) <- with_tz(terra::time(era_rast_tz) , tzone = timezone)
      
      # Subset stack to exclude the times that run past specified year due to 
      # time zone adjustment, and to exclude the previous year that was read in 
      # for time zone adjustment
      #
      era_rast_tz <- subset(era_rast_tz, with_tz(terra::time(era_rast_tz) , tzone = timezone) >=
                              as.POSIXct(paste0(year, "-01-01 01:00:00"), tz = timezone))
      era_rast_tz <- subset(era_rast_tz, with_tz(terra::time(era_rast_tz) , tzone = timezone) <=
                              as.POSIXct(paste0(year + 1, "-01-01 00:00:00"), tz = timezone))
      
      # Get n layers
      #
      layer_n <- nlyr(era_rast_tz)
      
      ##################### Daily Aggregation ######################################
      # Convert our time sequence to a factor format. This will allow for use as 
      # a grouping variable in assessing daily level summary measures
      #
      # Create a numeric sequence for each date in sequence
      #
      dates <- substr(with_tz(terra::time(era_rast_tz),  tzone = timezone), 1, 10) 
      
      # Convert our time sequence to a factor format. This will allow for use as 
      # a grouping variable in assessing daily level summary measures
      #
      daily_factor <- as.factor(c(dates[1], dates[1:length(dates)-1]))
      
      # Ensure time zone is assigned
      #
      time(era_rast_tz) <- with_tz(terra::time(era_rast_tz) , tzone = timezone)
      
      # RUN DAILY AGGREGATION
      # Tracker for viewing progress
      #
      cat("Now processing daily aggregation \n")
      
      # Aggregate to daily mean temperature
      #
      daily_mean <- tapp(era_rast_tz, daily_factor, fun = mean)
      
      # Aggregate to daily maximum temperature
      #
      daily_max <- tapp(era_rast_tz, daily_factor, fun = max)
      
      # Aggregate to daily minimum temperature
      #
      daily_min <- tapp(era_rast_tz, daily_factor, fun = min)
      
      # Set names for ERA5 variables based on input raster naming
      #
      mean_name <- paste0(varname, "_mean")
      max_name <- paste0(varname, "_max")
      min_name <- paste0(varname, "_min")
      
      # Add to lists
      #
      min_rasts[[timezone]] <- daily_min
      mean_rasts[[timezone]] <- daily_mean
      max_rasts[[timezone]] <- daily_max
    }
    
    # Merge into one raster if needed
    #
    if (length(max_rasts) == 1) {
      min_rast_all <- min_rasts[[1]]
      mean_rast_all <- mean_rasts[[1]]
      max_rast_all <- max_rasts[[1]]
    } else {
      min_rast_all <- do.call(merge, min_rasts)
      mean_rast_all <- do.call(merge, mean_rasts)
      max_rast_all <- do.call(merge, max_rasts)
    }
    
    # Write daily files. We can use these for percentiles and other estimations
    # in the future
    #
    writeRaster(min_rast_all, 
                paste0(ecmw_dir, "daily/", varname, "_", year, "_dailymin.tif"),
                overwrite = TRUE)
    writeRaster(mean_rast_all, 
                paste0(ecmw_dir, "daily/", varname, "_", year, "_dailymean.tif"),
                overwrite = TRUE)
    writeRaster(max_rast_all, 
                paste0(ecmw_dir, "daily/", varname, "_", year, "_dailymax.tif"),
                overwrite = TRUE)
    
    # In addition to writing the daily files, we will get annual average metrics
    # for each year
    #
    min_rast_ann <- app(min_rast_all, mean)
    mean_rast_ann <- app(mean_rast_all, mean)
    max_rast_ann <- app(max_rast_all, mean)
    
    # Add names for data
    #
    names(min_rast_ann) <- paste0(varname, "_min_", year)
    names(mean_rast_ann) <- paste0(varname, "_mean_", year)
    names(max_rast_ann) <- paste0(varname, "_max_", year)
    
    # Combine the raster layers to a single raster stack for the metric and year
    #
    metrics_annual <- c(min_rast_ann, mean_rast_ann, max_rast_ann)
    
    # Write annual files. 
    #
    writeRaster(metrics_annual, 
                paste0(ecmw_dir, "annual/", varname, "_", year, "_annualmetrics.tif"),
                overwrite = TRUE)
    
  }
  
}

