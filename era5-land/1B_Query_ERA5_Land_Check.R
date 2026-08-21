#
# Description: Code to check if all ERA5 downloaded
#
# Note: The ERA5 query occasionally crashes for a handful of months/variables.
# This script will tell you what has been downloaded
#
# First set directory where downloads were written.
#
ecmw_dir <-  "<INSERT_PATH_FOR_DOWNLOADS_HERE>/hourly/"   # Full pathway of the directory where your ERA5 rasters will be stored after download. 
# This should be the exact same as in script 1
#
# List files for each of the variables and years queried
# All of these should have 12 months. If there are any missing, check
# in the trac_dir from script 1 to see if there is a download link available.
# If there is not one available, use script 1 to rerun for that month by
# updating.
#     To make changes, adjust year at line 175 - 176
#     Set only needed months at line 212 - 214 (query_starts and query_ends)
#     Set only needed variables at line 219
#
# It is recommended to save the adjusted script 1 in a separate file so you
# have the code for the complete query still avaialble
#
list.files(ecmw_dir, pattern = ".*2m_temperature2023.*")
list.files(ecmw_dir, pattern = ".*2m_temperature2024")
list.files(ecmw_dir, pattern = ".*2m_dewpoint_temperature2023.*")
list.files(ecmw_dir, pattern = ".*2m_dewpoint_temperature2024.*")
