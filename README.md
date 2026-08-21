# PRISM-800m and ERA5-Land Data Query and Linkage
This repository includes R scripts for the query of PRISM-800m and ERA5-Land temperature data, the aggregation from hourly to daily and annual metrics for ERA5-Land, and the extraction of daily PRISM-800m and annual ERA5-Land metrics to address geocoordinates.

## Overview
Separate folders in the repository have been set up to store end-to-end data query and linkage for two temperature datasets commonly used in temperature and health studies. 

The prism folder includes scripts for the query and linkage of PRISM-800m temperature data. PRISM is a daily high-resolution coverage across the US available from 1981 to near-present; it is widely used in public health and climate studies. The coverage limited to CONUS, and no sub-daily estimates. Data is available in either 800m or 4km resolution. The example code here downloads temperature rasters for all of CONUS for two years. The high spatial resolution leads to this being a time and storage consuming process. On a local machine, we found that downloading these data took about 6 hours. The time frame can be expected to be vary based on your computer system.

The era5-land folder includes scripts for the query, temporal aggregation (from hourly to daily and annual), and linkage of ERA5-Land temperature and dew point temperature data. ERA5-Land is one of the few datasets available globally with many available variables and a long historical extent (1950 to near-present). The spatial resolution of ERA5-Land is 9km, substantially larger than PRISM-800m, but appropriate for health studies at scales like the county or GADM2 administrative boundary. Large data volume with the hourly time step can make download and data storage complicated. The example code here downloads temperature and dew point temperature rasters only for Los Angeles county for two years. This query is done with the ecmfwr R package, and requires an account to be set up with the Copernicus Climate Data Store (see [emwfr page](https://github.com/bluegreen-labs/ecmwfr) for details!). ERA5-Land data is downloaded at an hourly time step. The second script in this folder reads in the downloaded hourly files and aggregates based on the local time zone to a 24-hour (local midnight to midnight) daily minimum, mean, and maximum measure for both temperature and dew-point temperature. These daily values are written to files and then also aggregated to derive annual metrics, representing the average of the daily minimum, mean, and maximum of each measure. There are many approaches to derive summaries of temperature metrics across seasons or months, please read [Gause et al., 2026](https://link.springer.com/article/10.1007/s40572-026-00553-7#Sec2) for more information!

Each folder includes a linkage script which takes daily rasters for PRISM and annual summary rasters for ERA5-Land and extracts the temperature metrics to coordinates. For this example, we created a sample of random points nested within Los Angeles county for a demonstration of the extraction process. These points are included in the test_data folder.

## Dependencies
Packages used in this repository include:
- library("ecmwfr")         for era5 data query
- library("terra")          for raster data
- library("sf")             for vector data
- library("plyr")           for data management

## References
Reference on data considerations for temperature data in epidemiology studies:
- Gause, E.L., Feldscher, T., Popp, Z. et al. Data Considerations for Estimating Ambient Heat Exposure for Environmental Epidemiological Studies. Curr Envir Health Rpt 13, 32 (2026). https://doi.org/10.1007/s40572-026-00553-7

PRISM-800m reference:
- PRISM Group, Oregon State University, https://prism.oregonstate.edu, accessed [DATE OF DOWNLOAD].

ECMWFR package reference:
- Hufkens, K., R. Stauffer, & E. Campitelli. (2019). ecmwfr: Programmatic interface to the two European Centre for Medium-Range Weather Forecasts API services. Zenodo. http://doi.org/10.5281/zenodo.2647531.

ERA5-Land reference:
- J. Muñoz-Sabater, Dutra, E., Agustí-Panareda, A., Albergel, C., Arduini, G., Balsamo, G., Boussetta, S., Choulga, M., Harrigan, S., Hersbach, H., Martens, B., Miralles, D. G., Piles, M., Rodríguez-Fernández, N. J., Zsoter, E., Buontempo, C., and Thépaut, J.-N.: ERA5-Land: A state-of-the-art global reanalysis dataset for land applications, Earth Syst. Sci. Data,13, 4349–4383, 2021. https://doi.org/10.5194/essd-13-4349-2021.

