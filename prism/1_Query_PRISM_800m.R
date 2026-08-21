####################################
## Bulk download PRISM data, 800m ##
####################################

# Written By: Zach Popp
# Edited by: Emma Gause
# Date: 08/12/26
# Last updated: 08/18/26


library("plyr")
library("doBy")
library("tidyverse")
sf_use_s2(FALSE)  # S2 is for computing distances, areas, etc. on a SPHERE (using
# geographic coordinates, i.e., lat/lon in decimal-degrees); no need for this
# extra computational processing time if using PROJECTED coordinates,
# since these are already mapped to a flat surface. Here, PRISM
# is indeed in geographic coordinates, but the scale of areas we are 
# interested in is very small, and hence the error introduced by 
# ignoring the Earth's curvature over these tiny areas is negligible and
# a reasonable trade off given the dramatic reduction in processing time. Moreover,
# the areas we calculate are not an integral part of the process
# and any error in that step would not materially impact the final output

# Check package version numbers
#
if (packageVersion("plyr")  < "1.8.7"    | 
    packageVersion("doBy")  < "4.6.19"   |
    packageVersion("tidyverse") < "1.3.1") {
  cat("WARNING: one or more packages are outdated. Please update packages to prevent potential errors. \n") }

# %%%%%%%%%%%%%%%%%%%%%%% USER-DEFINED PARAMETERS %%%%%%%%%%%%%%%%%%%%%%%%%%%% #

input_data_dir <- "..."   # Full pathway of the directory where your input data will be stored.
# ** If you change this, be sure to keep the final forward slash **
# "Input data" is any data set that is *not* the final, analytical dataset.

zip_file_dir <- "..." # Set the directory for where the .zip PRISM files
# will be saved. If changing this directory, 
# be sure to keep the final forward slash


# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% #
# %%%%%%%%%%%%%%%%%% DOWNLOAD PRISM DATA FROM FTP %%%%%%%%%%%%%%%%%%%% #
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% #
#
# This script downloads raw PRISM data at the 800m resolution. Appriximately 4km 
# resolution PRISM data is also available from the PRISM Climate Group website.
# Researchers will have to decide whether their specific application requires 
# this highly resolved data - many might not. Also note that the higher-resolution 
# product does not resolve urban heat islands; the modeling methodology does not 
# incorporate urbanization characteristics such as LST, albedo, or imperviousness 
# of surfaces (which are proxy indicators of UHI). 

# Please also note that downaloding multiple variables of multiple years of 800m
# PRISM data takes a considerable investment in time. For example, a recent test
# downloading two years of two PRISM variables took approximately 6 hours to run
# on a local machine. 
#
options(timeout=1000) # Set the max timeout (in seconds) for downloading files

# Identify the PRISM variables that you want to download using the syntax from
# the PRISM FTP. For the purpose of this tutorial, we are just using "tmax" and "tmin".
# All options available: c("tmax", "tmean", "tmin", "ppt", "tdmean", "vpdmax", "vpdmin")
#
vars <- c("tmax", "tmin")

# The baseline URL for the PRISM FTP directory for daily data. Note that
# other time steps are available as well. Explore the FTP site to find the
# relevant URL and syntax for the data sets that you need.
#
URL <- "https://data.prism.oregonstate.edu/time_series/us/an/800m/"

# Identify the years of data you need. NOTE: data < 6 months old are provisional.
# Use "stable" data whenever possible, and note that the filename will be different
# for provisional data (you will have to modify the code below accordingly).
#
years_data <- c(2023:2024) # If downloading multiple years, enter range here, e.g., 2010:2020

for (i in 1:length(vars)) { 
  
  var <- vars[i]
  
  cat("---------------------------------------------------------------------\n")
  cat("Beginning download of", var, "PRISM data: variable", i, "of", length(vars), "\n")
  
  for (j in 1:length(years_data)) {
    
    year_data <- years_data[j]
    
    cat(".....Processing", year_data, "data \n")
    
    # Identify all of the days in that particular year in the format YYYYMMDD
    # This step is needed to account for Leap Days
    #
    days <- format(seq(as.Date(paste0(year_data, "-01-01")),
                       as.Date(paste0(year_data, "-12-31")), by = "days"),
                   format="%Y%m%d")
    
    for (k in 1:length(days)) {
      
      day <- days[k]
      
      dl_link <- paste0(URL, var, "/daily/", year_data, "/prism_", var, "_us_30s_", days[k], ".zip")
      dl_file <- paste0(zip_file_dir, "PRISM_", var, "_us_30s_", day, ".zip")
      
      # Check to see if the file already exists; download if not
      #
      if (file.exists(dl_file)) {
        
        cat("Zip file for day", day, "already downloaded. Proceeding to next day. \n")
        
      } else {
        
        dl <- try(download.file(dl_link, destfile = dl_file))
        
        # Determine if the download failed
        #
        if (class(dl) == "try-error") {
          
          cat("ERROR! File did not download successfully for", day, "\n")
          cat("..... Pausing for 10 seconds and re-trying. \n")
          
          k <- 10
          while (k > 0) {
            
            cat("..... Attempt", ((10 - k) + 1), "out of 10... \n")
            Sys.sleep(10) # Pause for 10 seconds
            dl <- try(download.file(dl_link, destfile = dl_file))
            
            if (class(dl) != "try-error") { 
              
              cat("..... :) success! Moving on to next file \n"); break 
              
            } else {
              
              cat("..... :( unsuccessful! \n")
              k <- k - 1 
            }
          }
          
          if (k == 0) { cat("..... Error unresolved; file for", day, "has still not been downloaded. \n"); break }
          
        } else { cat(":) file for", day, "downloaded successfully \n") }   
      }
      
      # Unzip the downloaded files
      # Recommended to delete the original zip files manually after downloading is complete
      #
      unzip(dl_file, exdir = paste0(input_data_dir, var, "/")) 
        #This places the unzipped files into a file within the input directory named after each variable. 
        # Create these folders yourself prior to running this code 
    }
  }
}
