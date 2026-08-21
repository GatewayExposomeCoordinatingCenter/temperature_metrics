#
# Description: Code to download ERA5-Land hourly raster data for temperature
# and dew point temperature
#
# Overview: 
#     This code uses the ecmwfr R package to download hourly ERA5 temperature 
#     measures from The Copernicus Climate Data Store. More details on the ERA5 
#     API access using the ecmwfr R package are accessible at:
#         https://github.com/bluegreen-labs/ecmwfr
#
#     Please explore the vignettes provided and note the provided instructions
#     for how to sign up for a Copernicus account and to access the relevant
#     user and key inputs below required to query data.
#
#       NOTE: YOU WILL NEED TO MAKE AN ACCOUNT AND ENTER YOUR CREDENTIALS
#       IN R IN ORDER TO DOWNLOAD THESE DATA USING THIS SCRIPT. More details
#       on account setup and API key extraction and setup are below!
#
#       NOTE: This download process relies on use of parallel submissions to
#       the Copernicus query system. Downloads will occassionally fail here.
#       Where this is the case, you can subset the script to get the specific
#       years/months/variables needed, or you can also see the log files
#       written out by the script to see if there is a link from which data
#       can be manually recovered.
#
# Authors: Zach Popp (zpopp@bu.edu), Allison James (alliej@bu.edu)
# Date Created: 08/20/2026
# Version Number: v1
#
# Instructions:
#
##################### Account Creation #########################################
##### Brief Overview of Account Creation: 
##### 1. Create an ECMWF account by self-registering. 
##### Follow https://github.com/bluegreen-labs/ecmwfr?tab=readme-ov-file
#####  under section "Use: ".
##### 2. Visit user profile to get personal access token. 
##### Follow https://github.com/bluegreen-labs/ecmwfr?tab=readme-ov-file
##### under section "Use:".
##### 3. Visit user profile to accept the terms and conditions in the 
#####  profile page. 
##### 4. Go to ERA-5 land page following 
##### https://cds-beta.climate.copernicus.eu/datasets/reanalysis-era5-land?tab=overview 
##### under section "Data Requests". Go to "Terms of use" block to accept 
##### the data licence to use products.
##### 5. Visit user profile page again to double check that Dataset licences 
##### to use Copernicus products shows up there and 
##### has been accepted. 
#
#     The Copernicus Climate Data Store API restricts the number of requests
#     actively running at a given time. Requests will sit in a queue, which
#     can be monitored at https://cds.climate.copernicus.eu/requests?tab=all
#
#     Smaller requests move more quickly through the queue. In order to 
#     maximize the request efficiency this request sets up separate requests
#     for the region of interest for each month/year and variable. Based 
#     on information shared through the CDS web forum, the number of hours
#     and number of variables will affect queue time, but the size of the area
#     typically will not. Depending on your time series and area of interest,
#     you may be required to divide your request due to limits on the maximum
#     download size for a single request. 
#
#     This script uses the wf_request function from the ecmwfr package
#     to submit all months of data for a single year and variable at once.
#     This will lead to all requests being added to the queue in short sequence.
#     The batches are submitted in a loop to allow for the addition of more
#     requests to the queue at a given time without waiting for requests to be
#     completed. 
#
#     Because the ecmwfr requires a user key to be provided, this script is set 
#     up to read encrypted text files where API credentials are stored from a 
#     directory. 
#     It is not recommended to save your API credentials in scripts given that 
#     they are sensitive information.
#
#     This example uses Los Angeles County, California as a test case. 
#     The shapefile for the extent is downloaded using the tigris package.
#
# Load required packages
#
library("ecmwfr")
library("sf")
library("dplyr")
library("tigris")
library("keyring") 

# Note: the keyring package may not be accessible in your computing
# environment. The package is used to provide a password that
# is otherwise requested directly during an interactive R 
# R Session. If the package cannot be used, this script can 
# be run in your session and the password provided directly.
#
# options(keyring_backend = "file") 
# This option may be required if you are using
# a cluster. It stores keyring variables in encrypted local files rather than 
# in your local environment. Try uncommenting this line if there are errors 
# in your logs like "Authentication failed" or "Cannot find password".

# Check package version numbers
#
if (packageVersion("ecmwfr") < "1.5.0"   | packageVersion("sf") < "1.0.16" ) {
  cat("WARNING: packages are outdated and may result in errors.") }

# %%%%%%%%%%%%%%%%%%%%%%% USER-DEFINED PARAMETERS %%%%%%%%%%%%%%%%%%%%%%%%%%%% #

# Set directory. Establishing this at the start of the script is useful in case
# future adjustments are made to the path. 
#
ecmw_dir <- "<INSERT_PATH_FOR_DOWNLOADS_HERE>/hourly/"   # Full pathway of the directory where your ERA5 rasters will be stored after download. 
# Note that this code is setup to nest within an 'hourly' subfolder. This can be
# changed, but will require updates in scripts 2 and 3 as well.
# ** If you change this, be sure to keep the final forward slash **
# "Input data" is any data set that is *not* the final, analytical dataset.

home_dir <- "<INSERT_PATH_FOR_APIKEY_HERE>" # Full pathway of the directory for the text file where your API credentials will be stored (more info.
# will be saved. If changing this directory, 
# be sure to keep the final forward slash

trac_dir <- "<INSERT_PATH_FOR_LOGS_HERE>"  # Full pathway of the directory for the text file where log files with information about each download will be stored.
# will be saved. If changing this directory, 
# be sure to keep the final forward slash

# Set region. This code is developed for Los Angeles County, California, 
# with the region representing its FIPS code. 
# This could be updated to reflect any subdivision of your area of interest, 
# as needed to divide processing into more computationally efficient steps.
#
# The download becomes increasingly more challenging for larger areas due to 
# rate limiting. If your region is extremely large (e.g., California) we 
# suggest running this script for each subregion 
# (e.g., counties within California).
#
region_in <- "06037"

# Read in key from file. See https://github.com/bluegreen-labs/ecmwfr for 
# details on accessing your key
#
# NOTE: The file storing your API key should never be shared publicly.
# In this script we store the API key in a text file. 
#
api_key <- scan(paste0(home_dir, "api_key.txt"), what = "", 
                nmax = 1, quiet = TRUE)

# Next, we will set your api key directly in the script using wf_set_key(). 
# Note that bash submission may not be effective with this approach, but the 
# data download can be done directly in your R session.
#
wf_set_key(key = api_key, user = "ecmwfr")

# After you have set this you can confirm it is store with the line below. The
# output in R should match your Copernicus profile. 
#
wf_get_key(user = "ecmwfr") 

# Identify extent for download.
# LOAD Shapefile. This approach involves a US application for Los Angeles County,
# California, downloaded using TIGRIS. 
# If you are conducting a global analysis or have an existing shapefile, 
# the below can be replaced to just set the shapefile_cut input:
#     shapefile_cut <- st_read("shapefile_path")
#
shapefile_cut <- tigris::counties(year = 2020)

# We will subset to LA County. This can be removed or modified based on what 
# shapefile is loaded in the previous line of code.
#
shapefile_cut <- shapefile_cut[shapefile_cut$GEOID == region_in, ]

# Set years to download - similar to geographic area, a larger range of years
# also affects download speed and queue times, and we suggest batching downloads
# longer than more than a few years.
#
minyear <- 2023
maxyear <- 2024

################### Build Requests #############################################

# Assess bounding box. The bounding box represents the coordinates of the 
# extent of the shapefile, and will be used to specify the area we would like
# to query from Copernicus Climate Data Store. The API will allow any bounding 
# parameters; however, values that deviate from the original model grid scale
# will be interpolated onto a new grid. Therefore, it’s recommended that for 
# ERA5-Land (which is 0.1˚ resolution) the bounding coordinates be divisible by 
# 0.1 (e.g., 49.5˚N, -66.8˚E, etc.), and that coordinates for ERA5 be divisible
# by 0.25 (e.g., 49.25˚N, -66.75˚E, etc.)
#
input_bbox <- st_bbox(shapefile_cut)

# Add a small buffer around the bounding box to ensure the whole region 
# is queried, and round the parameters to a 0.1 resolution. A 0.1 resolution
# is applied because the resolution of netCDF ERA5 data is .25x.25
# https://confluence.ecmwf.int/display/CKB/ERA5%3A+What+is+the+spatial+reference
#
input_bbox$xmin <- round(input_bbox$xmin[[1]], digits = 1) - 0.1
input_bbox$ymin <- round(input_bbox$ymin[[1]], digits = 1) - 0.1
input_bbox$xmax <- round(input_bbox$xmax[[1]], digits = 1) + 0.1
input_bbox$ymax <- round(input_bbox$ymax[[1]], digits = 1) + 0.1

# The set of inputs below specify the range of years to request, and sets
# the series of month state/end dates to query. There is 
# a limit on the data size that can be downloaded in a given request and smaller
# requests move more quickly through the CDS API queue, so we set up month-
# and variable-level requests in an effort to increase the efficiency
#
query_years <- c(minyear:maxyear)

# Adjust the input years based on the time period for which you want
# to query data
#
query_starts <- c("01-01", "02-01", "03-01", "04-01", "05-01", "06-01", "07-01", 
                  "08-01", "09-01", "10-01", "11-01", "12-01")
query_ends <- c("01-31", "02-29", "03-31", "04-30", "05-31", "06-30", "07-31", 
                "08-31", "09-30", "10-31", "11-30", "12-31")

# Set variables list
#
all_vars <- c("2m_temperature",
              "2m_dewpoint_temperature")

# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% #
# %%%%%%%%%%%%%% DOWNLOAD ERA5-Land DATA USIING ECMWFR API %%%%%%%%%%%%%%%%%%% #
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% #
## The loop below should directly download to your directory.
# Using this loop for direct download can add to the download time as jobs will
# not be added to the queue during the process of files being written to your
# environment. To avoid this delay, you can use script 1A, which batches requests.
#
# Within the loop we use 'sink' to ensure all warnings and output are written
# to a text file. These text files will include text that can be uses to reference
# submitted and completed jobs, so that we can programmatically download the data.
#
# Loop through years, variables, and months
#
for (year in c(minyear:maxyear)) {
  for (var in c(all_vars)) {
    for (i in 1:length(query_starts)) {
      
      # Track progress
      #
      cat("Now processing month ", i, "\n")
      
      # Extract inputs for start and end based on list of dates at begin and 
      # end of months around month
      #
      query_1 <- query_starts[i]
      query_2 <- query_ends[i]
      
      # Establish query for date periods. This formats the date inputs
      # as they need to be formatted.
      #
      query_dates <- paste0(year, "-", query_1, "/", year, "-", query_2)
      print(query_dates)
      
      # Form yearvar, which we need to index list. One request list should
      # be submitted at a time
      # 
      yearvar <- paste0(var, year)
      
      
      # The below is the formatted API request language. All of the inputs
      # specified below in proper formatting can be identified by forming a 
      # request using the Copernicus CDS point-and-click interface for data
      # requests. https://cds.climate.copernicus.eu/cdsapp#!/dataset/reanalysis-era5-land?tab=form
      # Select the variables, timing, and netcdf as the output format, and then 
      # select "Show API Request" at the bottom of the screen. 
      #
      # Note that the target is the filename that will be exported to the path
      # specified in the next part of the script. If using a loop, ensure that
      # that the unique features of each request are noted in the output! Here
      # we have each of the year, variable, and months (all our loop parameters)
      # in the filename so we won't accidentally overwrite.
      #
      request_era <- list(
        dataset_short_name = "reanalysis-era5-land",
        product_type = "reanalysis",
        variable = c(var),
        date = query_dates,
        time = c('00:00', '01:00', '02:00',
                 '03:00', '04:00', '05:00',
                 '06:00', '07:00', '08:00',
                 '09:00', '10:00', '11:00',
                 '12:00', '13:00', '14:00',
                 '15:00', '16:00', '17:00',
                 '18:00', '19:00', '20:00',
                 '21:00', '22:00', '23:00'),
        data_format = "netcdf",
        download_format = "unarchived",
        area = c(input_bbox$ymax, input_bbox$xmin, input_bbox$ymin, input_bbox$xmax),
        target = paste0("era5-9km-country-", yearvar, "_", query_1, "_", query_2,"_", region_in, ".nc")
      )
      
      # Set up text connection to track processing. This will save the warnings
      # and output to a file on your device, which can then be read in to loop
      # and download.
      #
      log_conn <- textConnection("log_output", "w", local = TRUE)
      sink(log_conn, type = "output")
      sink(log_conn, type = "message")
      
      # We run the submission within a tryCatch function as an error will be 
      # generated by the fake file path. This will only come up after all
      # requests are in
      #
      tryCatch(
        
        # Run the API request - direct download, add /x/ as described above if
        # planning to attempt expedited download.
        submit <- wf_request(request_era, 
                             #user = "ecmwfr",
                             path = paste0(ecmw_dir), time_out = 100000)
        
        ,
        
        # If there is an error due to a file not being written to your environment,
        # we want the loop to keep going as the file can be recovered using script
        # 1C.
        error = function(e){
          cat("ERROR encountered:\n")
          cat(conditionMessage(e), "\n")
          print(e)
        }
      ) 
      
      # Stop capturing output to file
      #
      sink(NULL, type = "message")
      sink(NULL, type = "output")
      close(log_conn)
      
      # Update processing tracker
      #
      cat(yearvar, " done \n")
      
      # Save text warnings to file
      #
      writeLines(log_output, paste0(trac_dir, "console_test_", yearvar, i, "_", region_in, "_var.txt"))
    }
  }
}

