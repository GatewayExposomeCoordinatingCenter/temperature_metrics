#
# Description: Code to link geocoded points to PRISM 800m raster data to extract gridded values 
#
# Overview: This script will read in your participant address data, project the
# spatial data so that it is consistent with the spatial system used for PRISM
# exposure data and then link the participant address to a time series of raster
# exposure measurements for all the daily files in the specified directory.  
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
addrdir <- "[INSERT PATH TO ADDRESS DIRECTORY HERE]"
expdir <- "[INSERT PATH TO EXPOSURE DIRECTORY HERE]"
outdir <-"[INSERT PATH TO OUTPUT DIRECTORY HERE]" #keep in mind, these can be the same - whatever you prefer. 

#now specify file name for addresses 
address_file <- "name_of_file.csv" #could also be an .rds, .shp, .gpkg, etc.

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
participants_shp <- participants[c("ID")]

####################### Exposure Link ##########################################

# Set list of exposures
# These should match the name of the folders in your "expdir" where each exposure is saved
exp_path_list <- c(
  "Tmax",
  "Tmin"
)


# Set tracker for progress
#
n_processed <- 0

# Loop through exposure folders. We will process each exposure once at a time
# and output a dataset that has each exposure linked to the time-varying 
# participant addresses. 
# 
for (exp_type in c(exp_path_list)) {
  
  #create an empty dataframe to store results of the looped extractions
  df0 <- NULL
  
  # Document start time
  #
  t1 <- Sys.time()
  
  # list the raster files we'll be reading in
  #
  exp_files_in <- list.files(path = paste0(expdir, exp_type),
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
  
  # Loop through files
  #
  for (f in exp_files_in){
    
    # Read in raster
    r <- rast(f)
    
    # Extract crs
    # 
    rast_crs <- crs(r)
    
    # Project points to raster crs
    #
    participants_shp <- project(participants_shp, rast_crs)
    
    # Update naming as needed so it is interpretable in output.
    # NOTE: Every unique exposure listed as an "exp_type" should have its own
    #       line below. Not all rasters need to be renamed, but this step also
    #       generates the name to be used in the output.
    #
    if (grepl("Tmax", f)) {
      name_out <- "Tmax"
    }
    
    if(grepl("Tmin", f)){
      name_out <- "Tmin"
    }
    
    # Extract exposure for all points
    exppts <- terra::extract(r, participants_shp)
    
    # Round all non ID cols - select the number of rounded digits you'd like to export
    #(this reduces data storage and also protects some individual privacy as long trailing digits can become identifiable for a given location)
    exppts <- exppts %>%
      mutate(across(-ID, ~ round(.x, 2)))
    
    # Bind to ID data
    exppts <- as_tibble(exppts)
    exppts <- bind_cols(as_tibble(participants_shp), exppts[, 2:length(names(exppts))]) 
    exppts$geometry <- NULL
    
    #add date from file name 
    #select the string locations with the date from the file path
    #nchar(exp_files_in) can help
    exppts <- exppts %>% mutate(date_chr = str_extract(f, "\\d{8}"), #this extracts the date from the file name
                                year = substr(date_chr, 1, 4),
                                month = substr(date_chr, 5, 6),
                                day = substr(date_chr, 7, 8),
                                date = ymd(paste0(year, "-", month, "-", day))) %>% 
      select(-year, -month, -day, -date_chr)
    
    #change the name of the column with the data values to allow for rbind
    names(exppts)[grepl("^prism_", names(exppts))] <- exp_type 
    
    #add to empty dataframe where results are being stored
    if (is.null(df0)) {
      df0 <- exppts
    } else {
      df0 <- rbind(df0, exppts)
    }
    
    
    # Clean up
    rm(r, exppts)
    invisible(gc())
    
    # Track progress
    if (f != tail(exp_files_in,1)) {
      cat("...", name_out, " data linked ... \n")
    }
    if (f == tail(exp_files_in,1)){
      cat("... All data linked!\n")
    }
    
    # save output one exposure at a time
    # keep in mind, df0 is a long file with participant IDs repeated for each raster date extracted
    write.csv(df0, paste0(outdir, "output_", exp_type, "_allpts.csv"), row.names = FALSE)
    
    
  }
  
  # Report N processed of total
  #
  n_total <- length(participants_shp$ID)
  
  # Track progress
  #
  n_processed <- n_processed + 1
  
  cat("Completed ", n_processed, " of ", length(exp_path_list), "!\n")

  t2 <- Sys.time()
  tdiff <- t2-t1
  print(tdiff)
  
}
