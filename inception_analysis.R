# ==============================================================================
# Inception Data Analysis
# ==============================================================================
# 
# EXPERIMENTAL REFACTORING of Inception_data_analysis_v2.3
# 
# Rating equation validation and diagnostics for EA Flood Forecasting & Warning
# 
# This is a reorganised version of the original monolithic analysis script.
# Analysis logic preserved but structure substantially revised. Test thoroughly
# before operational use.
# 
# Structure:
#   0. Setup: packages, configuration, helper functions
#   1-10. Ten independent analysis sections (run via Ctrl+Alt+T)
# 
# Navigate sections via outline dropdown (below code pane)
# 
# Dependencies: inception_functions_governed.R must be sourced first
# 
# Author: Environment Agency F&W team
# Maintainer: Jonathan Payne
# Version: 2.4 (experimental refactor)
# Last modified: 2026-05-01
# ==============================================================================


# Setup --------------------------------------------------------------------

# Source governed function library
# This must be loaded before running any analysis sections
source("inception_functions_governed.R")

# Package management
pkgs_cran <- c(
  "data.table", "ggplot2", "dplyr", "stringr", "scales",
  "RcppRoll", "magrittr", "reshape2", "cowplot", "webshot2",
  "jsonlite", "rootSolve", "afcolours", "plotly", "lubridate",
  "processx", "leaflet", "tools", "readr", "checkmate"
)

pkgs_versioned <- list(
  sf = "1.0-15",
  knitr = "1.45",
  rmarkdown = "2.29",
  gt = "0.10.1"
)

# Install missing CRAN packages
new_pkgs <- pkgs_cran[!(pkgs_cran %in% installed.packages()[, "Package"])]
if (length(new_pkgs)) install.packages(new_pkgs)

# Install versioned packages if missing
for (pkg in names(pkgs_versioned)) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    devtools::install_version(pkg, version = pkgs_versioned[[pkg]])
  }
}

# GitHub packages (commented: install once then load)
# devtools::install_github("JonPayneEA/riskyData")
# devtools::install_github("JonPayneEA/mappER")

# Load packages
library(riskyData)
library(mappER)
library(data.table)
library(ggplot2)
library(dplyr)
library(stringr)
library(scales)
library(cowplot)
library(gt)
library(sf)
library(leaflet)
library(afcolours)
library(plotly)
library(lubridate)

# Source helper functions
source("inception_functions.R")

# Configuration
ea_cols <- c("#008531", "#FDCA00", "#034B89", "#B2C326", 
             "#D95F15", "#54BCE7", "#820053")

# Table save format: ".pdf", ".png", or ".docx"
# pdf/png require Chrome via webshot2
# docx groups tables but appearance differs
tables_save_ext <- ".docx"

# Base directory for SPOL data
base_spol_dir <- "C:/Users/od000014/OneDrive - Defra/Useful model data links/"

# Output control
save_plots <- FALSE
write_dir <- "./output/"


# Data Import --------------------------------------------------------------

# TODO: This section needs user configuration
# 
# Required inputs:
#   - Level data: WISKI export or API call
#   - Flow data: WISKI export or API call
#   - Rating parameters: level_boundaries, a_param, b_param, c_param
#   - Date range: datetime_start, datetime_end
#   - Station metadata: site name, WISKI ID
#   - Flood thresholds: FAL, FW1, FW2, FW3, FW4 (if applicable)
#   - QMED for reference lines
#
# Example structure (uncomment and populate):

# # Import level data
# level_data <- wiski_export_to_r6(
#   file_name = "path/to/level_export.csv",
#   measure = "level",
#   site_name = "Example Gauge",
#   site_id = "123456"
# )
#
# # Import flow data
# flow_data <- wiski_export_to_r6(
#   file_name = "path/to/flow_export.csv",
#   measure = "flow",
#   site_name = "Example Gauge",
#   site_id = "123456"
# )
#
# # Define rating parameters
# level_boundaries <- c(1.5, 2.0, 3.0)  # Upper level per limb
# a_param <- c(0.0, 0.1, 0.2)           # Offset per limb
# b_param <- c(1.5, 1.8, 2.0)           # Exponent per limb
# c_param <- c(10.0, 15.0, 20.0)        # Coefficient per limb (capital C)
#
# # Date range
# datetime_start <- as.POSIXct("2023-01-01 00:00:00", tz = "GMT")
# datetime_end <- as.POSIXct("2023-12-31 23:45:00", tz = "GMT")
#
# # Flood thresholds (m)
# thresholds <- c(
#   FAL = 1.2,
#   FW1 = 1.5,
#   FW2 = 2.0,
#   FW3 = 2.5,
#   FW4 = 3.0
# )
#
# # Reference discharge
# qmed <- 50.0  # m3/s

# Validate data spans required range
if (exists("level_data") && exists("flow_data")) {
  
  # Check level data
  if (level_data$data$dateTime[[1]] > datetime_start ||
      level_data$data$dateTime[[nrow(level_data$data)]] < datetime_end) {
    stop("Level data does not span the entire date range")
  }
  
  # Check flow data
  if (is.na(flow_data$data$dateTime[[nrow(flow_data$data)]])) {
    stop("Flow data has empty last row(s). Remove in text editor.")
  }
  
  if (flow_data$data$dateTime[[1]] > datetime_start ||
      flow_data$data$dateTime[[nrow(flow_data$data)]] < datetime_end) {
    stop("Flow data does not span the entire date range")
  }
  
  # Trim to date range
  level_data$data <- level_data$data[
    dateTime >= datetime_start & dateTime <= datetime_end
  ]
  
  flow_data$data <- flow_data$data[
    dateTime >= datetime_start & dateTime <= datetime_end
  ]
}


# Rating Analysis: Level to Flow -------------------------------------------

if (exists("level_data") && exists("a_param")) {
  
  # Apply rating
  rated_flow <- data.frame(
    dateTime = level_data$data$dateTime,
    value = sapply(
      level_data$data$value,
      apply_rating,
      level_boundaries = level_boundaries,
      a = a_param,
      b = b_param,
      C = c_param
    ),
    name = "Rated"
  )
  
  # Observed flow
  obs_flow <- data.frame(
    dateTime = flow_data$data$dateTime,
    value = flow_data$data$value,
    name = "Observed"
  )
  
  # Difference
  diff_flow <- data.frame(
    dateTime = flow_data$data$dateTime,
    value = obs_flow$value - rated_flow$value,
    name = "Difference"
  )
  
  # Combine
  both_flow <- rbind(rated_flow, obs_flow, diff_flow)
  
  # Plot
  p_flow <- ggplot(both_flow, aes(dateTime, value, 
                                   colour = name, 
                                   linetype = name, 
                                   size = name)) +
    theme_bw() +
    geom_hline(
      yintercept = c(0, qmed),
      colour = "#111111",
      linetype = "dashed",
      linewidth = 0.5
    ) +
    geom_line() +
    ggtitle(
      label = paste("Rated vs observed flow at", flow_data$meta()$stationName)
    ) +
    theme(
      plot.title = element_text(
        face = "bold",
        colour = "#008531",
        size = 16
      )
    ) +
    labs(
      x = "Date",
      y = "Flow (m3/s)",
      subtitle = paste("Data from", datetime_start, "to", datetime_end)
    ) +
    scale_colour_manual(
      values = c("#9F9F9F", afcolours::af_colours("categorical")[c(1, 4)])
    ) +
    scale_linetype_manual(values = c(1, 1, 1)) +
    scale_size_manual(values = c(0.75, 1.25, 0.75)) +
    theme(legend.position = "bottom", legend.title = element_blank())
  
  print(p_flow)
  
  if (save_plots) {
    ggsave(
      filename = paste0(
        write_dir,
        flow_data$meta()$stationName[[1]],
        "_rated_flow_check.png"
      ),
      width = 200,
      height = 100,
      units = "mm",
      dpi = 300,
      bg = "white"
    )
  }
  
  # Clean up
  rm(rated_flow, obs_flow, diff_flow)
}


# Rating Analysis: Flow to Level -------------------------------------------

if (exists("flow_data") && exists("a_param")) {
  
  # Apply inverse rating
  rated_level <- data.frame(
    dateTime = flow_data$data$dateTime,
    value = sapply(
      flow_data$data$value,
      apply_inverse_rating,
      level_boundaries = level_boundaries,
      a = a_param,
      b = b_param,
      C = c_param
    ),
    name = "Rated"
  )
  
  # Observed level
  obs_level <- data.frame(
    dateTime = level_data$data$dateTime,
    value = level_data$data$value,
    name = "Observed"
  )
  
  # Difference
  diff_level <- data.frame(
    dateTime = level_data$data$dateTime,
    value = obs_level$value - rated_level$value,
    name = "Difference"
  )
  
  # Combine
  both_level <- rbind(rated_level, obs_level, diff_level)
  
  # Plot
  p_level <- ggplot(both_level, aes(dateTime, value,
                                     colour = name,
                                     linetype = name,
                                     size = name)) +
    theme_bw() +
    geom_hline(
      yintercept = c(0, thresholds),
      colour = "#111111",
      linetype = "dashed",
      linewidth = 0.5
    ) +
    geom_line() +
    ggtitle(
      label = paste("Rated vs observed level at", flow_data$meta()$stationName)
    ) +
    theme(
      plot.title = element_text(
        face = "bold",
        colour = "#008531",
        size = 16
      )
    ) +
    labs(
      x = "Date",
      y = "Level (m)",
      subtitle = paste("Data from", datetime_start, "to", datetime_end)
    ) +
    scale_colour_manual(
      values = c("#9F9F9F", afcolours::af_colours("categorical")[c(1, 4)])
    ) +
    scale_linetype_manual(values = c(1, 1, 1)) +
    scale_size_manual(values = c(0.75, 1.25, 0.75)) +
    theme(legend.position = "bottom", legend.title = element_blank())
  
  print(p_level)
  
  if (save_plots) {
    ggsave(
      filename = paste0(
        write_dir,
        flow_data$meta()$stationName[[1]],
        "_rated_level_check.png"
      ),
      width = 200,
      height = 100,
      units = "mm",
      dpi = 300,
      bg = "white"
    )
  }
  
  # Clean up
  rm(rated_level, obs_level, diff_level)
}
