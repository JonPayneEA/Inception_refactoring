# ==============================================================================
# Inception Analysis: Optimised Function Definitions
# ==============================================================================
# 
# Complete helper function library for hydrological data processing
# OPTIMISED VERSION with vectorisation, caching, and pure data.table
# 
# Dependencies:
#   - data.table: high-performance data manipulation (fastverse core)
#   - riskyData: EA hydrological data API wrapper (Flode package)
#   - mappER: EA spatial analysis toolkit (Flode package)
#   - sf: spatial data structures and operations
#   - checkmate: input validation and assertions
#   - magrittr: pipe operators (%>%)
#   - lubridate: date/time handling
# 
# Performance optimisations:
#   - Vectorised rating equation applications
#   - Cached WISKI file reads
#   - Pre-compiled regex patterns
#   - In-place data.table operations (no dplyr)
#   - Batch spatial operations
# 
# Coding standards:
#   - fastverse-aligned: data.table over tidyverse (governance requirement)
#   - Input validation via checkmate on all external functions
#   - Explicit returns
#   - Heavy inline comments explaining logic
#   - snake_case naming throughout
#   - British National Grid (EPSG:27700) for all spatial operations
# 
# Author: Environment Agency Flood Forecasting & Warning team
# Maintainer: Jonathan Payne
# Version: 2.5 (optimised)
# Last modified: 2026-05-01
# ==============================================================================


# ==============================================================================
# Global cache environments
# ==============================================================================

# WISKI file cache (avoids repeated I/O)
.wiski_cache <- new.env(parent = emptyenv())

# Compiled regex pattern cache
.regex_cache <- new.env(parent = emptyenv())


# ==============================================================================
# Utility functions
# ==============================================================================

#' Test whether numeric values are whole numbers
#' 
#' R's is.integer() tests storage class, not mathematical value. This function
#' tests whether numeric values are integer-valued within floating point
#' tolerance. Essential for validating loop indices, event counts, limb counts.
#' 
#' @param x numeric vector to test
#' @param tol numeric, tolerance for floating point comparison 
#'   (default: machine epsilon^0.5, approximately 1.5e-8)
#' 
#' @return logical vector, TRUE where values are integer-valued
#' 
#' @examples
#' is_wholenumber(c(1.0, 1.5, 2.0))  # TRUE, FALSE, TRUE
#' is_wholenumber(5.2e-16)  # TRUE (within tolerance)
#' is_wholenumber(54)  # TRUE
#' 
is_wholenumber <- function(x, tol = .Machine$double.eps^0.5) {
  
  # Input validation
  checkmate::assert_numeric(x, any.missing = TRUE)
  checkmate::assert_number(tol, lower = 0, finite = TRUE)
  
  # Test whether difference from rounded value is within tolerance
  # abs() handles both positive and negative deviations
  # Vectorised operation - processes entire vector at once
  result <- abs(x - round(x)) < tol
  
  return(result)
}


#' Remove everything after the nth comma in a string
#' 
#' WISKI CSV exports contain variable numbers of commas in the Remarks field,
#' which breaks standard CSV parsing. This function truncates strings at the
#' nth comma, allowing remarks to be discarded before re-parsing as proper CSV.
#' 
#' OPTIMISED: Uses cached compiled regex patterns for repeated calls with same n
#' 
#' Regex pattern breakdown: ^((?:[^,]*,){n}).*
#'   [^,]*      = sequence of zero or more non-comma characters
#'   (?:[^,]*,) = non-capturing group: non-commas followed by comma
#'   {n}        = exactly n repetitions of that group
#'   .*         = everything remaining on the line
#'   ^          = anchor to start of string
#'   (...)      = capturing group 1 - everything we want to keep
#' 
#' The sub() call replaces entire line with just group 1 (everything up to
#' and including the nth comma).
#' 
#' @param str character string to truncate
#' @param n integer, number of commas to retain (default: 1)
#' 
#' @return character string truncated after nth comma
#' 
#' @examples
#' drop_after_comma("a,b,c,d", n = 2)  # Returns "a,b,"
#' drop_after_comma("level,0.5,OK,gauge repaired, sensor drift", n = 3)
#'   # Returns "level,0.5,OK,"
#' 
drop_after_comma <- function(str, n = 1) {
  
  # Input validation
  checkmate::assert_character(str, any.missing = FALSE)
  checkmate::assert_int(n, lower = 1)
  
  # Check cache for pre-compiled pattern
  cache_key <- as.character(n)
  
  if (!exists(cache_key, envir = .regex_cache)) {
    # Build and cache regex pattern for this n
    pattern <- sprintf("^((?:[^,]*,){%d}).*", n)
    assign(cache_key, pattern, envir = .regex_cache)
  } else {
    pattern <- get(cache_key, envir = .regex_cache)
  }
  
  # Replace entire string with captured group (first n comma-delimited fields)
  # \\1 references the first (and only) capturing group
  # perl = TRUE enables faster PCRE engine
  result <- sub(pattern, "\\1", str, perl = TRUE)
  
  return(result)
}


#' Clear WISKI file cache
#' 
#' Removes all cached WISKI export data from memory. Use when memory constrained
#' or when files have been updated on disk and need re-reading.
#' 
#' @return NULL (invisibly)
#' 
#' @examples
#' clear_wiski_cache()
#' 
clear_wiski_cache <- function() {
  rm(list = ls(envir = .wiski_cache), envir = .wiski_cache)
  invisible(NULL)
}


# ==============================================================================
# Spatial analysis functions
# ==============================================================================

#' Intersect Voronoi polygons with catchment boundary
#' 
#' Temporary alternative to mappER::intersectPoly pending v2.1 update.
#' Used in Thiessen polygon analysis to clip raingauge Voronoi cells to
#' catchment boundaries and assign each clipped cell to its source gauge.
#' 
#' Process:
#' 1. Cast Voronoi geometry to ensure valid polygon structure
#' 2. Intersect with catchment boundary (clips polygons at edge)
#' 3. Convert to sf spatial dataframe with BNG coordinate system (EPSG:27700)
#' 4. Calculate centroids (more robust for nearest-feature joins)
#' 5. Join centroids to raingauge coordinates via nearest-feature matching
#' 6. Replace centroid geometry with original intersected polygons
#' 
#' The centroid step prevents spurious matches when polygon edges are very
#' close to multiple gauges. Centroids give single representative point per
#' Thiessen cell, ensuring correct gauge attribution.
#' 
#' @param voronoi sf object, Voronoi polygon tessellation around gauge points
#' @param catchment sf object, catchment boundary polygon (single feature)
#' @param coords sf object, raingauge point coordinates with attributes
#'   (must include stationName, WISKI, Easting, Northing at minimum)
#' 
#' @return sf object with columns:
#'   - V1: intersected polygon geometries (clipped to catchment)
#'   - gauge attributes joined from coords (stationName, WISKI, etc.)
#'   One row per clipped Thiessen cell
#' 
intersect_poly_test <- function(voronoi, catchment, coords) {
  
  # Input validation
  checkmate::assert_class(voronoi, "sf")
  checkmate::assert_class(catchment, "sf")
  checkmate::assert_class(coords, "sf")
  
  # Cast to ensure clean polygon structure
  # Handles MULTIPOLYGON / POLYGON type mismatches that can occur in
  # Voronoi generation at catchment boundaries
  cast <- sf::st_cast(voronoi)
  
  # Intersect Voronoi cells with catchment boundary
  # Only retains polygon portions inside catchment
  # st_intersection clips at catchment edge and discards exterior portions
  intersect <- sf::st_intersection(cast, catchment)
  
  # Convert to proper sf object with British National Grid CRS
  # EPSG:27700 is standard for EA spatial data
  intersect_sf <- sf::st_sf(intersect, crs = sf::st_crs(27700))
  
  # Calculate polygon centroids
  # These give single representative point per Thiessen cell
  # More robust than polygon edges for nearest-feature matching
  # Prevents edge cases where polygon vertices lie equidistant from two gauges
  centroids <- sf::st_centroid(intersect_sf)
  
  # Join centroids to raingauge coordinates via nearest feature
  # Each centroid gets attributes from its nearest gauge
  # This re-establishes the gauge->polygon relationship after intersection
  join <- sf::st_join(centroids, coords, join = st_nearest_feature)
  
  # Replace centroid geometry with original intersected polygons
  # Now we have full polygons with correct gauge attributes
  # V1 column name retained for compatibility with existing code
  join$V1 <- intersect_sf$intersect
  
  return(join)
}


# ==============================================================================
# Rainfall analysis functions
# ==============================================================================

#' Calculate average annual rainfall from gauge IDs
#' 
#' Computes AAR with standard error from complete hydrological years of daily
#' rainfall data. Handles data from either WISKI API or pre-exported CSV files.
#' 
#' Hydrological year runs 1 October to 30 September. Function identifies
#' complete years, calculates annual totals with optional rescaling for missing
#' data, then returns mean and standard error across all years.
#' 
#' Missing data handling:
#' - If rescale_missing = TRUE: annual total multiplied by N_days / N_valid
#'   (assumes missing data distributed representatively)
#' - If rescale_missing = FALSE: annual total calculated from available data only
#'   (underestimates if missing data occurs during wet periods)
#' - Years with zero valid data excluded entirely
#' 
#' @param gauge_ids character vector, WISKI station IDs (six digits)
#' @param use_api logical vector, TRUE for API call, FALSE for file read
#'   (must be same length as gauge_ids)
#' @param gauge_names character vector, station names when use_api = FALSE
#'   (ignored when use_api = TRUE, as names come from API)
#' @param data_files character vector, file paths for WISKI exports when
#'   use_api = FALSE. Set elements to NA to skip that gauge entirely.
#' @param read_dir character, directory containing data files (default: ~/)
#' @param rescale_missing logical, adjust annual totals for missing data
#'   (default: TRUE, recommended for operational gauges with <10% missing)
#' 
#' @return data.frame with columns:
#'   - SiteName: station name (from API or gauge_names)
#'   - AAR: average annual rainfall (mm)
#'   - AARsd: standard error on AAR (mm)
#'   - AARstart: start date of data used (DD/MM/YYYY)
#'   - AARend: end date of data used (DD/MM/YYYY)
#'   One row per gauge in gauge_ids
#' 
get_gauge_aar <- function(gauge_ids,
                          use_api = TRUE,
                          gauge_names = NULL,
                          data_files = NULL,
                          read_dir = "~/",
                          rescale_missing = TRUE) {
  
  # Input validation
  checkmate::assert_character(gauge_ids, min.len = 1)
  checkmate::assert_logical(use_api, len = length(gauge_ids))
  checkmate::assert_character(gauge_names, null.ok = TRUE)
  checkmate::assert_character(data_files, null.ok = TRUE)
  checkmate::assert_directory_exists(read_dir)
  checkmate::assert_flag(rescale_missing)
  
  # Pre-allocate output vectors for efficiency
  n_gauges <- length(gauge_ids)
  gauge_name <- character(n_gauges)
  gauge_aar <- numeric(n_gauges)
  gauge_aar_error <- numeric(n_gauges)
  gauge_start <- character(n_gauges)
  gauge_end <- character(n_gauges)
  
  # Loop over gauges
  for (i in seq_along(gauge_ids)) {
    
    # Load data from API
    if (use_api[i]) {
      
      # Call WISKI API for daily rainfall (86400s period, total type)
      # datapoints = "all" retrieves full available record
      site_r1 <- riskyData::loadAPI(
        ID = gauge_ids[i],
        measure = "rainfall",
        period = 86400,
        type = "total",
        datapoints = "all"
      )
      
      # Ensure chronological order
      # loadAPI can occasionally shuffle rows if multiple requests paginated
      site_r1$postOrder()
      
    } else if (is.na(data_files[i])) {
      
      # No data source specified - record NA and skip to next gauge
      gauge_aar[i] <- NA
      gauge_aar_error[i] <- NA
      gauge_name[i] <- gauge_names[i]
      gauge_start[i] <- NA
      gauge_end[i] <- NA
      
      next  # Skip remaining processing for this gauge
      
    } else {
      
      # Load from WISKI export file (uses cache if available)
      site_r1 <- wiski_export_to_r6_cached(
        file_name = paste0(read_dir, data_files[[i]]),
        measure = "rainfall",
        site_name = gauge_names[i],
        site_id = gauge_ids[i]
      )
    }
    
    # Clean invalid values
    # Negative rainfall physically impossible - treat as sensor error
    # data.table in-place modification for efficiency
    site_r1$data[value < 0, value := NA]
    
    # Add hydrological year columns
    # riskyData method adds hydroYear and hydroYearDay to data.table
    site_r1$hydroYearDay()
    
    # Get record length
    nt <- nrow(site_r1$data)
    
    # Calculate day-of-year shift to align all years to 365 days
    # Accounts for leap years by removing 29 Feb from the count
    # This ensures years are comparable even when record spans leap years
    hyd_end <- site_r1$data$hydroYearDay[nt]
    
    # shift_end = 1 if last day falls after 28 Feb in a leap year, else 0
    shift_end <- (mod(site_r1$data$hydroYear[nt], 4) == 0) * 
                 (site_r1$data$hydroYearDay[nt] > 152)
    
    # Shift all days after 28 Feb back by 1 in leap years
    # mod(..., 365) wraps to create 365-day years
    # data.table in-place column creation
    site_r1$data[, shift_year_day := mod(
      hydroYearDay - 
        (mod(hydroYear, 4) == 0) * (hydroYearDay > 152) - 
        hyd_end - shift_end - 1,
      365
    ) + 1]
    
    # Assign year numbers (shift_year = 1, 2, 3, ...)
    # Use data.table's shift() for efficient lagged comparison
    site_r1$data[, shift_year := cumsum(shift_year_day == 1)]
    
    # Remove incomplete year 0 (partial year at start of record)
    site_r1$data <- site_r1$data[shift_year >= 1]
    
    # Calculate annual totals for each complete hydrological year
    # Use data.table grouped operations for efficiency
    yr_summary <- site_r1$data[, .(
      n_days = .N,
      n_valid = sum(!is.na(value)),
      total = sum(value, na.rm = TRUE)
    ), by = shift_year]
    
    # Apply rescaling if requested and filter out years with no data
    if (rescale_missing) {
      yr_summary[, rescaled_total := total * n_days / pmax(n_valid, 1)]
      yr_totals <- yr_summary[n_valid > 0, rescaled_total]
    } else {
      yr_totals <- yr_summary[n_valid > 0, total]
    }
    
    # Calculate AAR statistics
    # mean() gives average annual rainfall across all complete years
    gauge_aar[i] <- mean(yr_totals)
    
    # Standard error = sd / sqrt(n)
    # Quantifies uncertainty in AAR estimate due to inter-annual variability
    gauge_aar_error[i] <- sd(yr_totals) / sqrt(length(yr_totals))
    
    # Record metadata
    gauge_name[i] <- site_r1$meta()$stationName
    
    # Format dates as DD/MM/YYYY
    gauge_start[i] <- format(
      as.POSIXct(site_r1$data$dateTime[[1]], tz = "UTC"),
      "%d/%m/%Y"
    )
    
    gauge_end[i] <- format(
      as.POSIXct(site_r1$data$dateTime[[nrow(site_r1$data)]], tz = "UTC"),
      "%d/%m/%Y"
    )
  }
  
  # Construct output data.table (faster than data.frame)
  result <- data.table(
    SiteName = gauge_name,
    AAR = gauge_aar,
    AARsd = gauge_aar_error,
    AARstart = gauge_start,
    AARend = gauge_end
  )
  
  return(result)
}


#' Calculate Thiessen polygon weights for raingauges
#' 
#' Generates Voronoi tessellation around gauge points, clips to catchment
#' boundary, and calculates area-based weights for spatial averaging.
#' 
#' Thiessen (Voronoi) polygons divide space so each point is closest to one
#' gauge. Weight = polygon area / catchment area gives proportional contribution
#' of each gauge to catchment-average rainfall.
#' 
#' Side effects:
#' - Creates global variables: boundingBoxMin, boundingBoxMax, RGnames,
#'   coordsDt, ThiessenW (retained for compatibility with existing workflows)
#' - Optionally writes shapefile if write_sf = TRUE
#' - Optionally plots catchment with polygons if plot_catchment = TRUE
#' 
#' @param gauge_ids character vector, WISKI station IDs
#' @param catch_name character, catchment shapefile name (with .shp extension)
#' @param readdir character, directory containing catchment shapefile
#'   (default: empty string for current directory)
#' @param writedir character, output directory for optional shapefile
#'   (default: empty string for current directory)
#' @param write_sf logical, save intersected polygons as shapefile
#'   (default: FALSE)
#' @param plot_catchment logical, generate plot of catchment with polygons
#'   (default: TRUE, displays in active graphics device)
#' @param use_api logical vector, TRUE to get coordinates from API, FALSE to
#'   use manual coordinates from gauge_en (must match length of gauge_ids)
#' @param gauge_names character vector, station names when use_api = FALSE
#'   (ignored when use_api = TRUE)
#' @param gauge_en list of numeric vectors, Easting/Northing pairs when
#'   use_api = FALSE. Each element is c(Easting, Northing) in metres BNG.
#'   (ignored when use_api = TRUE)
#' 
#' @return list with components:
#'   - weights: numeric vector of area-based weights (sum = 1)
#'   - voronoi: sf object with intersected polygons
#'   
#' @details
#' Bounding box extends 1km beyond catchment boundary to ensure Voronoi
#' generation captures all gauges that might influence edge cells.
#' 
get_thiessen <- function(gauge_ids,
                         catch_name,
                         readdir = "",
                         writedir = "",
                         write_sf = FALSE,
                         plot_catchment = TRUE,
                         use_api = TRUE,
                         gauge_names = NULL,
                         gauge_en = NULL) {
  
  # Input validation
  checkmate::assert_character(gauge_ids, min.len = 1)
  checkmate::assert_character(catch_name, len = 1)
  checkmate::assert_character(readdir, len = 1)
  checkmate::assert_character(writedir, len = 1)
  checkmate::assert_flag(write_sf)
  checkmate::assert_flag(plot_catchment)
  checkmate::assert_logical(use_api, len = length(gauge_ids))
  
  # Load catchment shapefile
  # mappER::loadCatchment handles .shp extension automatically
  ctchmnt <- mappER::loadCatchment(filepath = paste0(readdir, catch_name))
  
  # Calculate bounding box with 1km buffer
  # Used to define extent for Voronoi generation
  # geometry[[1]][[1]] accesses coordinate matrix from sf polygon structure
  coords_matrix <- ctchmnt$geometry[[1]][[1]]
  
  bbox_min <- c(
    min(coords_matrix[, 1]) - 1000,
    min(coords_matrix[, 2]) - 1000
  )
  
  bbox_max <- c(
    max(coords_matrix[, 1]) + 1000,
    max(coords_matrix[, 2]) + 1000
  )
  
  # Assign to global environment for compatibility with existing code
  # Some downstream functions expect these variables to exist globally
  assign("boundingBoxMin", bbox_min, pos = .GlobalEnv)
  assign("boundingBoxMax", bbox_max, pos = .GlobalEnv)
  
  # Build gauge coordinate table
  # Pre-allocate for efficiency
  n_gauges <- length(gauge_ids)
  name_list <- character(n_gauges)
  coords_list <- vector("list", n_gauges)
  
  for (i in seq_along(gauge_ids)) {
    
    if (use_api[i]) {
      
      # Get gauge metadata from API
      # period = 900 (15-minute), datapoints = "earliest" just to get coords
      site_r1 <- riskyData::loadAPI(
        ID = gauge_ids[i],
        measure = "rainfall",
        period = 900,
        type = "total",
        datapoints = "earliest"
      )
      
      # Extract station name
      name_list[i] <- site_r1$meta()$stationName[1]
      
      # Extract coordinates
      # coords() method returns data.table with Easting, Northing, Lat, Long
      coords_list[[i]] <- site_r1$coords()
      
    } else {
      
      # Use manually specified name and coordinates
      name_list[i] <- gauge_names[i]
      
      # Construct coordinate row
      # Lat/Long set to 0 as not used in BNG-based Thiessen calculation
      coords_list[[i]] <- data.table(
        stationName = gauge_names[i],
        WISKI = gauge_ids[i],
        Easting = gauge_en[[i]][1],
        Northing = gauge_en[[i]][2],
        Latitude = 0,
        Longitude = 0
      )
    }
  }
  
  # Combine coordinate rows efficiently with rbindlist
  coords_table <- rbindlist(coords_list)
  
  # Assign to global environment (compatibility requirement)
  assign("RGnames", name_list, pos = .GlobalEnv)
  assign("coordsDt", coords_table, pos = .GlobalEnv)
  
  # Convert to sf points object
  # coords argument specifies which columns contain Easting, Northing
  # crs = 27700 sets British National Grid coordinate system
  gauges <- sf::st_as_sf(
    x = coords_table,
    coords = c("Easting", "Northing"),
    crs = 27700
  )
  
  # Generate Voronoi polygons and intersect with catchment
  # mappER::intersectPoly wraps Voronoi generation + intersection + weighting
  # writeSF and filepath control optional shapefile output
  voronoi <- mappER::intersectPoly(
    coords = gauges,
    catchment = ctchmnt,
    writeSF = write_sf,
    filepath = writedir,
    filename = tools::file_path_sans_ext(catch_name)
  )
  
  # Plot if requested
  # mappER::plotCatchment displays catchment with coloured Thiessen cells
  if (plot_catchment) {
    mappER::plotCatchment(voronoi)
  }
  
  # Calculate area-based weights
  # st_area returns area in m^2, so ratio is dimensionless
  # Weights sum to 1.0 (each gauge contributes proportionally to its cell area)
  weights <- as.numeric(sf::st_area(voronoi$V1)) / 
             as.numeric(sf::st_area(ctchmnt))
  
  # Assign to global environment (compatibility requirement)
  assign("ThiessenW", weights, pos = .GlobalEnv)
  
  # Return both weights and spatial object
  result <- list(
    weights = weights,
    voronoi = voronoi
  )
  
  return(result)
}


# ==============================================================================
# Seasonality and event functions
# ==============================================================================

#' Convert date to angle for polar seasonality plots (vectorised)
#' 
#' Maps calendar date to angle in degrees for polar plotting. Used in
#' performance testing event seasonality analysis to show temporal distribution
#' of flood events on a circular plot.
#' 
#' OPTIMISED: Fully vectorised - processes entire date vector at once
#' 
#' Convention: 1 January = 90 degrees (top of circle), angles increase clockwise
#' 
#' Leap year handling: 29 Feb assigned same angle as 28 Feb to maintain
#' 365-day circle even in leap years. All subsequent dates in leap year shifted
#' back by one day-equivalent angle.
#' 
#' @param date Date vector or POSIXct timestamps
#' 
#' @return numeric vector, angles in degrees (0-360)
#'   - 0/360 degrees = 1 October (start of hydrological year, right of circle)
#'   - 90 degrees = 1 January (top of circle)
#'   - 180 degrees = 1 April (left of circle)
#'   - 270 degrees = 1 July (bottom of circle)
#' 
#' @examples
#' date_to_angle(as.Date(c("2020-01-01", "2020-04-01")))
#' 
date_to_angle <- function(date) {
  
  # Input validation
  checkmate::assert_date(date)
  
  # Extract day of year (1-366) - vectorised
  day_num <- lubridate::yday(date)
  
  # Extract year for leap year testing - vectorised
  yr <- lubridate::year(date)
  
  # Check if leap year - vectorised
  # Leap years: divisible by 4, except centuries unless divisible by 400
  is_leap <- (magrittr::mod(yr, 4) == 0) &
             (magrittr::mod(yr, 400) == 0 | magrittr::mod(yr, 100) != 0)
  
  # Apply leap year correction - fully vectorised
  # If leap year AND on or after 29 Feb (day 59), shift back by 1 day
  # Subtract 2 because 29 Feb (day 60) needs to map to day 58's angle
  day_adjusted <- ifelse(
    is_leap & day_num >= 59,
    day_num - 2,
    day_num - 1
  )
  
  # Convert to angle - vectorised
  # Add 90*(1-360/365) to rotate so 1 Jan is at top of circle
  angle <- day_adjusted * (360 / 365) + 90 * (1 - 360 / 365)
  
  return(angle)
}


#' Convert angle to season name (vectorised)
#' 
#' Maps polar plot angle to meteorological season name. Used to colour-code
#' event markers in seasonality plots.
#' 
#' OPTIMISED: Fully vectorised using cut() for batch classification
#' 
#' Meteorological seasons (Northern Hemisphere):
#' - Spring: March, April, May (approx 58-149 degrees)
#' - Summer: June, July, August (approx 149-234 degrees)
#' - Autumn: September, October, November (approx 234-329 degrees)
#' - Winter: December, January, February (329-360 and 0-58 degrees)
#' 
#' @param angle numeric vector, angles in degrees (0-360)
#' 
#' @return character vector, season names
#' 
#' @examples
#' angle_to_season(c(90, 180, 270))  # "Winter", "Summer", "Autumn"
#' 
angle_to_season <- function(angle) {
  
  # Input validation
  checkmate::assert_numeric(angle, lower = 0, upper = 360)
  
  # Vectorised classification using cut
  # Breaks define season boundaries
  # Labels assign season names
  # right = FALSE means interval is [lower, upper)
  season <- cut(
    angle,
    breaks = c(0, 58, 149, 234, 329, 360),
    labels = c("Winter", "Spring", "Summer", "Autumn", "Winter"),
    right = FALSE,
    include.lowest = TRUE
  )
  
  # Convert factor to character
  season <- as.character(season)
  
  return(season)
}


# ==============================================================================
# Hypsometric analysis
# ==============================================================================

#' Calculate percentage of catchment area above gauge elevation
#' 
#' Linear interpolation on hypsometric curve (elevation vs cumulative area).
#' Used to calculate elevation-dependent raingauge weights based on vertical
#' position within catchment.
#' 
#' Logic:
#' - If gauge below minimum catchment elevation: 100% of catchment above it
#' - If gauge above maximum catchment elevation: 0% of catchment above it
#' - Otherwise: linearly interpolate between neighbouring points on curve
#' 
#' @param gauge_elev numeric, gauge elevation in metres above ordnance datum (mAOD)
#' @param elevations numeric vector, catchment elevations from hypsometric curve
#'   (must be monotonically increasing)
#' @param percentages numeric vector, percentage of catchment area above each
#'   elevation (must be monotonically decreasing, same length as elevations)
#' 
#' @return numeric, percentage of catchment area above gauge elevation (0-100)
#' 
#' @examples
#' # Catchment from 100m to 400m elevation
#' elev <- c(100, 200, 300, 400)
#' perc <- c(100, 75, 40, 0)
#' 
#' get_gauge_perc(150, elev, perc)  # ~87.5 (interpolated between 100m and 200m)
#' get_gauge_perc(50, elev, perc)   # 100 (below catchment)
#' get_gauge_perc(450, elev, perc)  # 0 (above catchment)
#' 
get_gauge_perc <- function(gauge_elev, elevations, percentages) {
  
  # Input validation
  checkmate::assert_number(gauge_elev, finite = TRUE)
  checkmate::assert_numeric(elevations, min.len = 2, any.missing = FALSE)
  checkmate::assert_numeric(percentages, len = length(elevations), any.missing = FALSE)
  
  # Handle gauge below catchment
  if (gauge_elev < min(elevations)) {
    return(100)
  }
  
  # Handle gauge above catchment
  if (gauge_elev > max(elevations)) {
    return(0)
  }
  
  # Find bracketing points on hypsometric curve
  # findInterval is optimised for this use case
  # Find first elevation higher than gauge
  i <- findInterval(gauge_elev, elevations, rightmost.closed = FALSE)
  
  # Ensure we have valid bracket (i and i+1)
  if (i == 0) i <- 1
  if (i == length(elevations)) i <- length(elevations) - 1
  
  # Linear interpolation between points i and i+1
  # Solve y = m*x + c for x (percentage) given y (gauge elevation)
  # 
  # Slope of line connecting (percentages[i], elevations[i]) to
  # (percentages[i+1], elevations[i+1])
  m <- (elevations[i + 1] - elevations[i]) / 
       (percentages[i + 1] - percentages[i])
  
  # Intercept: rearrange y = m*x + c to c = y - m*x
  # Use point i+1 for numerical stability
  c_int <- elevations[i + 1] - m * percentages[i + 1]
  
  # Solve for percentage: x = (y - c) / m
  result <- (gauge_elev - c_int) / m
  
  return(result)
}


# ==============================================================================
# WISKI import functions
# ==============================================================================

#' Read WISKI export file and convert to riskyData R6 object (cached)
#' 
#' Wrapper around wiski_export_to_r6 that implements file-level caching.
#' Repeated reads of the same file return cached result (avoids I/O bottleneck).
#' 
#' @param file_name character, path to WISKI export CSV file
#' @param measure character, data type: "level", "flow", or "rainfall"
#' @param site_name character, descriptive name for gauge
#' @param site_id character, WISKI station ID (six digits)
#' 
#' @return riskyData R6 object from cache or fresh read
#' 
#' @examples
#' # First call reads file
#' data1 <- wiski_export_to_r6_cached("gauge.csv", "level", "Thames", "123456")
#' 
#' # Second call returns cached result (instant)
#' data2 <- wiski_export_to_r6_cached("gauge.csv", "level", "Thames", "123456")
#' 
wiski_export_to_r6_cached <- function(file_name, 
                                       measure = "level", 
                                       site_name = "defaultName", 
                                       site_id = "000000") {
  
  # Create cache key from file path
  # Normalise path to handle relative vs absolute
  cache_key <- normalizePath(file_name, mustWork = FALSE)
  
  # Check if result already cached
  if (exists(cache_key, envir = .wiski_cache)) {
    return(get(cache_key, envir = .wiski_cache))
  }
  
  # Not in cache - read file
  result <- wiski_export_to_r6(file_name, measure, site_name, site_id)
  
  # Store in cache
  assign(cache_key, result, envir = .wiski_cache)
  
  return(result)
}


#' Read WISKI export file and convert to riskyData R6 object
#' 
#' WISKI CSV exports have variable comma counts in the Remarks field, breaking
#' standard CSV parsing. This function:
#' 1. Reads as pipe-delimited fixed-width
#' 2. Truncates remarks field (removes commas beyond expected count)
#' 3. Writes clean temporary CSV
#' 4. Reads with data.table::fread
#' 5. Populates riskyData R6 object for compatibility with Flode workflows
#' 
#' R6 object structure:
#' - $data: data.table with columns dateTime (POSIXct) and value (numeric)
#' - $meta(): method returning list of station metadata
#' - $coords(): method returning coordinates (level/flow only)
#' 
#' @param file_name character, path to WISKI export CSV file
#' @param measure character, data type: "level", "flow", or "rainfall"
#'   (determines expected column structure and units)
#' @param site_name character, descriptive name for gauge (e.g. "Thames at Kingston")
#' @param site_id character, WISKI station ID (six digits, e.g. "521410")
#' 
#' @return riskyData R6 object (HydroImportFactory class) with populated:
#'   - data slot: data.table(dateTime, value)
#'   - metadata: stationName, WISKI, parameter, unitName, timeZone
#'   
#' @details
#' Temporary file temp_data.csv created in working directory, automatically
#' deleted after read. Flow exports have inconsistent unit formatting
#' ([m3/s] vs [m³/s]) requiring special column name handling.
#' 
#' Date format expected: DD/MM/YYYY HH:MM:SS
#' Timezone: GMT (no daylight saving adjustment)
#' WISKI metadata skipped: first 15 rows
#' 
wiski_export_to_r6 <- function(file_name, 
                                measure = "level", 
                                site_name = "defaultName", 
                                site_id = "000000") {
  
  # Input validation
  checkmate::assert_file_exists(file_name)
  checkmate::assert_choice(measure, choices = c("level", "flow", "rainfall"))
  checkmate::assert_character(site_name, len = 1)
  checkmate::assert_character(site_id, len = 1)
  
  # Set measure-specific parameters
  # Flow and level have 7 columns before remarks, rainfall has 5
  params <- switch(
    measure,
    flow = list(unit_str = "m3/s", remarks_col = 7),
    rainfall = list(unit_str = "mm", remarks_col = 5),
    list(unit_str = "m", remarks_col = 7)  # default to level
  )
  
  # Read as pipe-delimited to preserve comma structure
  # Entire line read as single string due to sep = "|"
  # This prevents commas in remarks from being interpreted as delimiters
  tmpdt <- read.table(
    file_name,
    sep = "|",
    quote = "",
    colClasses = "character",
    stringsAsFactors = FALSE,
    comment.char = "",
    blank.lines.skip = FALSE,
    na.strings = "",
    skip = 0
  )
  
  # Truncate each line after nth comma
  # Removes remarks field which contains unpredictable comma count
  # Uses cached regex pattern for efficiency
  tmpdt <- sapply(tmpdt, drop_after_comma, n = params$remarks_col - 1)
  
  # Write cleaned data to temporary CSV
  write.table(
    tmpdt,
    file = "./temp_data.csv",
    append = FALSE,
    quote = FALSE,
    sep = ",",
    row.names = FALSE,
    col.names = FALSE
  )
  
  # Read with data.table for speed and robustness
  # skip = 15 discards WISKI metadata header
  # header = TRUE uses row 16 as column names
  dt <- data.table::fread(
    "./temp_data.csv",
    skip = 15,
    header = TRUE
  )
  
  # Clean up temporary file
  file.remove("./temp_data.csv")
  
  # Create R6 container with metadata
  # HydroImportFactory is riskyData class for time series data
  site_r6 <- riskyData::HydroImportFactory$new(
    data = NA,  # Populated below
    dataType = "Raw Import",
    stationName = site_name,
    WISKI = site_id,
    parameter = measure,
    unitName = params$unit_str,
    start = NA,  # Auto-populated from data
    end = NA,    # Auto-populated from data
    timeZone = "GMT"
  )
  
  # Populate data slot with measure-specific column handling
  if (measure == "flow") {
    
    # Flow exports have inconsistent unit formatting in column headers
    # [m3/s] vs [m³/s] depending on WISKI version
    # Force column names to avoid fread misinterpretation
    setnames(
      dt,
      old = names(dt),
      new = c("dateTime", "Value", "StateOfValue", "Runoff", "Quality", "Tags", "Remarks")
    )
    
    # Extract dateTime and value columns
    # Parse dateTime to POSIXct, cast value to numeric
    # data.table in-place column selection
    site_r6$data <- dt[, .(
      dateTime = as.POSIXct(dateTime, format = "%d/%m/%Y %H:%M:%S", tz = "GMT"),
      value = as.numeric(Value)
    )]
    
  } else if (measure == "rainfall") {
    
    # Rainfall exports have standard column headers
    site_r6$data <- dt[, .(
      dateTime = as.POSIXct(`Time stamp`, format = "%d/%m/%Y %H:%M:%S", tz = "GMT"),
      value = as.numeric(`Value [mm]`)
    )]
    
  } else {
    
    # Level exports have standard column headers
    site_r6$data <- dt[, .(
      dateTime = as.POSIXct(`Time stamp`, format = "%d/%m/%Y %H:%M:%S", tz = "GMT"),
      value = as.numeric(`Value [m]`)
    )]
  }
  
  return(site_r6)
}


# ==============================================================================
# Rating functions (vectorised)
# ==============================================================================

#' Apply multi-limb rating equation to level data (vectorised)
#' 
#' Power-law rating: Q = C * (h - a)^b
#' 
#' OPTIMISED: Fully vectorised using findInterval for limb selection and
#' vectorised arithmetic. Processes entire level vector in single pass.
#' 
#' Multi-limb structure allows different relationships at different stage ranges,
#' accommodating:
#' - Low-flow rectangular weirs (b ≈ 1.5)
#' - Mid-flow transitions
#' - High-flow compound sections (b ≈ 2.5-3)
#' 
#' Limb selection: findInterval assigns each level to appropriate limb.
#' Parameters must have equal length (one value per limb). Boundaries define
#' upper limit of each limb. Lower limit is previous boundary (or zero for
#' lowest limb).
#' 
#' @param h numeric vector, water levels in metres (stage)
#' @param level_boundaries numeric vector, upper level for each limb (m)
#'   Must be monotonically increasing
#' @param a numeric vector, offset parameter per limb (m)
#'   Represents effective zero flow level for each limb
#' @param b numeric vector, exponent parameter per limb (dimensionless)
#'   Typical range 1-3, determines rating curve shape
#' @param C numeric vector, coefficient parameter per limb (discharge units)
#'   Capital C retained as hydraulics convention
#'   Units: (m^3/s) / (m^b)
#' 
#' @return numeric vector, discharge in m³/s. Returns 0 where rating produces NaN
#'   (e.g. negative base with non-integer exponent). Preserves NA in input.
#' 
#' @examples
#' # Two-limb rating: low flow (b=1.5) up to 1m, high flow (b=2) above
#' h_values <- c(0.3, 0.5, 0.8, 1.2, 1.5)
#' q_values <- apply_rating_vectorised(
#'   h = h_values,
#'   level_boundaries = c(1.0, 2.0),
#'   a = c(0.0, 0.1),
#'   b = c(1.5, 2.0),
#'   C = c(10.0, 15.0)
#' )
#' 
apply_rating_vectorised <- function(h, 
                                    level_boundaries, 
                                    a, 
                                    b, 
                                    C) {
  
  # Input validation
  checkmate::assert_numeric(h, any.missing = TRUE)
  checkmate::assert_numeric(level_boundaries, min.len = 1, any.missing = FALSE)
  checkmate::assert_numeric(a, len = length(level_boundaries))
  checkmate::assert_numeric(b, len = length(level_boundaries))
  checkmate::assert_numeric(C, len = length(level_boundaries))
  
  # Pre-allocate result vector
  q <- numeric(length(h))
  
  # Find limb index for each level value
  # findInterval returns index of interval: 0 if below all, 1 for first interval, etc.
  # Add 1 because our limbs are 1-indexed
  # rightmost.closed = TRUE means boundary values use upper limb
  limb_idx <- findInterval(h, level_boundaries, rightmost.closed = TRUE) + 1
  
  # Cap at maximum limb index (for levels above highest boundary)
  limb_idx <- pmin(limb_idx, length(level_boundaries))
  
  # Apply rating equation by limb
  # Process all values for each limb in batch (vectorised)
  for (i in seq_along(level_boundaries)) {
    
    # Mask for values in this limb
    mask <- limb_idx == i & !is.na(h)
    
    if (!any(mask)) next  # Skip if no values in this limb
    
    # Apply rating equation to all values in this limb at once
    # Vectorised arithmetic throughout
    q[mask] <- C[[i]] * (h[mask] - a[[i]])^b[[i]]
  }
  
  # Handle invalid results
  # NaN occurs if (h - a) negative and b non-integer
  # This can happen at limb transitions if offset not set correctly
  q[is.nan(q)] <- 0
  
  # Preserve NA from input
  q[is.na(h)] <- NA
  
  return(q)
}


#' Apply inverse rating equation to flow data (vectorised)
#' 
#' Solves power-law rating for level given discharge: h = (Q/C)^(1/b) + a
#' 
#' OPTIMISED: Fully vectorised using findInterval for limb selection.
#' 
#' Handles gaps between rating limbs (discontinuities where curves don't meet).
#' If discharge falls in gap, returns boundary level between the two limbs.
#' 
#' Algorithm:
#' 1. Calculate discharge at each boundary from limb below
#' 2. Calculate discharge at each boundary from limb above
#' 3. If input Q between these values, return boundary level (in gap)
#' 4. Otherwise invert equation for appropriate limb
#' 
#' @param q numeric vector, discharge in m³/s
#' @param level_boundaries numeric vector, upper level for each limb (m)
#' @param a numeric vector, offset parameter per limb (m)
#' @param b numeric vector, exponent parameter per limb (dimensionless)
#' @param C numeric vector, coefficient parameter per limb
#' 
#' @return numeric vector, water level in metres. Returns boundary level where
#'   discharge falls in gap between limbs. Returns 0 where discharge below
#'   lowest limb. Preserves NA in input.
#' 
#' @examples
#' # Invert two-limb rating
#' q_values <- c(1.0, 3.54, 10.0, 20.0)
#' h_values <- apply_inverse_rating_vectorised(
#'   q = q_values,
#'   level_boundaries = c(1.0, 2.0),
#'   a = c(0.0, 0.1),
#'   b = c(1.5, 2.0),
#'   C = c(10.0, 15.0)
#' )
#' 
apply_inverse_rating_vectorised <- function(q, 
                                            level_boundaries, 
                                            a, 
                                            b, 
                                            C) {
  
  # Input validation
  checkmate::assert_numeric(q, any.missing = TRUE)
  checkmate::assert_numeric(level_boundaries, min.len = 1, any.missing = FALSE)
  checkmate::assert_numeric(a, len = length(level_boundaries))
  checkmate::assert_numeric(b, len = length(level_boundaries))
  checkmate::assert_numeric(C, len = length(level_boundaries))
  
  # Pre-allocate result vector
  h <- numeric(length(q))
  
  # Calculate discharge at each boundary using limb below
  # This gives upper discharge limit for each limb
  below_boundaries <- C * (level_boundaries - a)^b
  
  # Construct lower boundary levels
  # Lowest limb starts at level 0
  # Each subsequent limb starts at previous upper boundary
  len <- length(level_boundaries)
  if (len == 1) {
    lower_boundaries <- 0
  } else {
    lower_boundaries <- c(0, level_boundaries[1:(len - 1)])
  }
  
  # Calculate discharge at each boundary using limb above
  # This gives lower discharge limit for next limb up
  above_boundaries <- C * (lower_boundaries - a)^b
  
  # Replace NaN with zero
  # NaN occurs if (boundary - a) negative and b non-integer
  # Interpret as zero flow at that configuration
  below_boundaries[is.nan(below_boundaries)] <- 0
  above_boundaries[is.nan(above_boundaries)] <- 0
  
  # Find applicable limb for each discharge value
  # findInterval with vec argument finds intervals for vector
  limb_idx <- findInterval(q, below_boundaries, rightmost.closed = TRUE) + 1
  
  # Cap at maximum limb index
  limb_idx <- pmin(limb_idx, length(level_boundaries))
  
  # Process each limb
  for (i in seq_along(level_boundaries)) {
    
    # Mask for values nominally in this limb
    mask <- limb_idx == i & !is.na(q)
    
    if (!any(mask)) next  # Skip if no values in this limb
    
    # Check if discharge falls in gap between limbs
    # Gap exists where above_boundary > below_boundary from previous limb
    if (i > 1) {
      # Values in gap between limb i-1 and limb i
      in_gap <- mask & q < above_boundaries[[i]]
      
      # Return boundary level for values in gap
      h[in_gap] <- level_boundaries[[i - 1]]
      
      # Update mask to exclude gap values
      mask <- mask & !in_gap
    } else {
      # First limb: values below lowest flow return zero
      below_lowest <- mask & q < above_boundaries[[i]]
      h[below_lowest] <- 0
      mask <- mask & !below_lowest
    }
    
    # Invert equation for remaining values in this limb
    # h = (Q/C)^(1/b) + a
    # Vectorised arithmetic
    if (any(mask)) {
      h[mask] <- (q[mask] / C[[i]])^(1 / b[[i]]) + a[[i]]
    }
  }
  
  # Preserve NA from input
  h[is.na(q)] <- NA
  
  return(h)
}


# ==============================================================================
# End of file
# ==============================================================================
