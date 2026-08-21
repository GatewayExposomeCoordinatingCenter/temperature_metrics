#
# Description: Code to link geocoded points to ERA5-Land annual raster data to 
# extract gridded values 
#
# Overview: This script will read in your participant address data, project the
# spatial data so that it is consistent with the spatial system used for 
# ERA5-Land  exposure data and then link the participant address to all years
# and metrics in the processed era5_land/annual/ populated in script 2.
# The output will include a single file with all years and metrics bound 
# together.
#
# Author: Zach Popp (zpopp@bu.edu)
# Modified from: Cam Reimer (cjreimer@bu.edu)
# Contributor: Allison James (alliej@bu.edu)
# Contributor: Emma Gause (egause@bu.edu)
#
# Date Created: 08/20/2026
# Version Number: v1
#
# Instructions: 
#     - Make sure that your gridded exposure data is downloaded and saved on
#       your device, or better yet a computing cluster.
#
#     - You address or point location dataset can be saved in the same folder 
#       as the gridded datasets, or not. You will specify the path to each
#       dataset separately.
#
#     - The script is set up to ingest participant address data in a .csv file 
#       with columns ID, Year, X and Y. If your data is spatial, columns should
#       include ID, Year, and geometry.
#       
#     - You will have to update the folder paths to match where your data live. 
#       You can choose to specify input and output directories separately. 
#
# ------------------------------------------------------------------------------

# Load packages - if you are an R user, and have already installed the below,
# then remove from list
#
#install.packages(c("terra", "sf", "dplyr", "tidyverse"))

library("terra")  # For raster data
library("sf")     # For vector data
library("dplyr")
library("tidyverse")

# Check package version numbers
#
if (packageVersion("terra") < "1.5.34"   | packageVersion("sf") < "1.0.7" | 
    packageVersion("tidyverse") < "1.3.1" | packageVersion("lwgeom") < "0.2.8") {
  cat("WARNING: packages are outdated and may result in errors.") }

# %%%%%%%%%%%%%%%%%%%%%%% USER-DEFINED PARAMETERS %%%%%%%%%%%%%%%%%%%%%%%%%%%% #

# Specify your directory paths below, always ending in "/"
# NOTE: Currently, this should work for .gpkg, .shp, .csv. Can add more 
#       file support as we hear from cohorts about their data
#
addrdir <- "<INSERT_PATH_FOR_POINTDATA_HERE>" # This is where address data is stored
expdir <- "<INSERT_PATH_FOR_DOWNLOADS_HERE>" # This should be the path to where the annual rasters are stored (ending in /annual/)
outdir <-"<INSERT_PATH_FOR_LINKED_OUTPUT_HERE?" # This is where the final linked data will go. 

#now specify file name for addresses 
address_file <- "random_points_LA_county.csv" # Could also be an .rds, .shp, .gpkg, etc. This is path to test data, but should be replaced by your filename

# If your data is in a .shp, .gpkg use "Spatial"
# If your data is in a .rds, .csv use "Non-Spatial
#
data_format_in <- "Non-Spatial"

# NOTE: This will need to be updated based on column names for:
#             participant ID, lon column, lat column

# %%%%%%%%%%%%%%%%%%%% READ IN POINTS %%%%%%%%%%%%%%%%%%%%%%% #
# Read in patient address points - use if/else based on whether data is in 
# spatial format or tabular with lat/lon
#
if (data_format_in == "Spatial") {
  participants_in <- read_sf(paste0(addrdir, address_file))
  
  participants <- participants_in %>%
    group_by(ID, geometry) %>%   ### Column names for ID, and geometry
    slice(1) %>% #this removes any duplicates 
    ungroup()
  
  participants <- vect(address_file)
} else if (data_format_in == "Non-Spatial") {
  participants_in <- read.csv(paste0(addrdir, address_file))
  
  # filter down to 1 row for each unique ID/address combination 
  dat <- participants_in %>%
    group_by(ID, X, Y) %>%    ### Column names for ID, Longitude, and Latitude
    slice(1) %>%
    ungroup()
  
  #in this step, we create points from column data - specify the crs that matches your data
  participants <- vect(dat, geom = c('X', 'Y'), crs = "epsg:4326", keepgeom = TRUE)  
  ### Values in 'geom' must match column names for lon/lat
}

# Remove lat/lon cols
#
participants_shp <- participants[c("ID", "Year")]

####################### Exposure Link ##########################################

#create an empty dataframe to store results of the looped extractions
#
df0 <- NULL

# Document start time
#
t1 <- Sys.time()

# Set name of exposure for output
#
exp_type <- "era5_annual_d2m_t2m"

# list the raster files we'll be reading in
#
exp_files_in <- list.files(path = paste0(expdir),
                           pattern = '.*.tif$', #update grid file type if necessary (e.g. .bil)
                           full.names = TRUE, 
                           recursive = TRUE)


# %%%%%%%%%%%%%%%%%%%%%% EXTRACT EXPOSURE VALUES FOR ALL POINTS %%%%%%%%%%%% #
# 
# In this step, we will use the address data and extract the exposure
# underlying each address. We loop through the rasters to limit the amount
# of data stored in R at any given time. Keep in mind, the PRISM rasters that
# you previously downloaded include a national (contiguous) file for each day.  
#
# %%%%%%%%%%%%%%%%%%%%%%%%%%% READ IN THE EXPOSURE RASTER DATA %%%%%%%%%%%%% #

# create an empty dataframe to store results of the looped extractions'
#
df0 <- NULL

# Loop through files
#
for (f in exp_files_in){
  
  
  # Read in raster
  #
  r <- rast(f)
  
  # Extract crs
  # 
  rast_crs <- crs(r)
  
  # Project points to raster crs
  #
  participants_shp <- project(participants_shp, rast_crs)
  
  # Add uid 
  #
  participants_shp$uid <- c(1:length(participants_shp$ID))
  
  # Print name of data being linked
  #
  name_out <- basename(f)
  name_out <- gsub("_annualmetrics.tif", "", name_out)
  cat(name_out, "\n")
  
  # Extract exposure for all points
  #
  exppts <- terra::extract(r, participants_shp)
  
  # Bind to ID data
  exppts <- as_tibble(exppts)
  exppts <- bind_cols(as_tibble(participants_shp), exppts[, 2:length(names(exppts))]) 
  exppts$geometry <- NULL
  
  # For ERA5-Land, we will have some points that do not bind due to ERA5
  # masking any data where their 9km grid cells would include > 50% water.
  # To get an estimate of temperature for these individuals we can joint them
  # to the nearest avaialble point
  #
  exppts_na <- exppts[is.na(exppts[4]),]
  participants_shp_na <- participants_shp[
    participants_shp$uid %in% exppts_na$uid, 
  ]
  exppts_joined <- exppts[
    !exppts$uid %in% exppts_na$uid, 
  ]
  
  # Save the NA participants as an sf object
  #
  participants_shp_na <- st_as_sf(participants_shp_na)
  
  # Vectorize raster to extract
  #
  r_v <- as.points(r)
  exp_data_sf <- st_as_sf(r_v)
  
  # Find nearest raster pixel for each facility
  #
  pts_out <- st_join(participants_shp_na, exp_data_sf, 
                     join = st_nearest_feature)
  
  # Remove spatial features and add flag about join type
  #
  pts_out <- as.data.frame(pts_out)
  pts_out$flag_nearjoin <- 1
  
  # Prepare to join with terra linked data
  #
  pts_out <- as_tibble(pts_out)
  pts_out$geometry <- NULL
  
  # Add flags for linked data
  #
  exppts_joined$flag_nearjoin <- 0
  
  # Bind datasets
  #
  exppts_all <- rbind(exppts_joined, pts_out)
  
  # Round all non ID cols - select the number of rounded digits you'd like to export
  # (this reduces data storage and also protects some individual privacy as 
  # long trailing digits can become identifiable for a given location)
  #
  exppts_all <- exppts_all %>%
    mutate(across(-ID, ~ round(.x, 2)))
  
  # Remove uid
  #
  exppts_all$uid <- NULL

  # Add to empty dataframe where results are being stored
  # We bind by ID, Year (this representing the year of the participant address),
  # and the flag for if a join was near water. Since we are joining points to
  # the same grid of ERA5-Land cells across metrics, this should be consistent.
  # If there is a flag that indicates an error here or a many-to-many join,
  # that may suggest some issue with the ERA5 metrics processing in steps 1 
  # and 2 (i.e., misaligned grid cells). Alternatively this could arise if
  # "ID" and "Year" combinations are not unique in the participant data (for
  # example, if someone has multiple addresses in a given year). If that is the
  # case remove the line of code above that removed uid from the data frame,
  # and join on uid in addition to ID and Year (or some other identifier
  # specific to each address)
  #
  # 
  if (is.null(df0)) {
    df0 <- exppts_all
  } else {
    df0 <- left_join(df0, exppts_all,
                     by = c("ID", "Year", "flag_nearjoin"))
  }
  
  # Clean up
  rm(r, exppts_all, exppts, exppts_joined, pts_out, participants_shp_na)
  invisible(gc())
  
  # Track progress
  if (f != tail(exp_files_in,1)) {
    cat("...", name_out, " data linked ... \n")
  }
  if (f == tail(exp_files_in,1)){
    cat("... All data linked!\n")
  }
  
}

# Finally, save the file with all linked metrics
#
write.csv(df0,
          paste0(outdir, "output_", exp_type, "_allpts.csv"))
