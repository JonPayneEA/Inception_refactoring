# Inception Data Analysis

**EXPERIMENTAL REFACTORING** — This is a reorganised version of the original `Inception_data_analysis_v2.3` script. The analysis logic is preserved but structure, naming, and documentation have been substantially revised. Test thoroughly before operational use.

Refactored hydrological analysis toolkit for gauge rating validation, rainfall weighting, and performance testing diagnostics.

## Structure

**inception_functions_governed.R** — Complete function library with governance adherence
- WISKI import (handles variable comma counts in remarks)
- Rating equations (forward and inverse, multi-limb)
- Spatial analysis (Thiessen polygons, catchment intersection)
- Rainfall metrics (AAR calculation with missing data handling)
- Seasonality (polar plot angle conversions)
- Hypsometric analysis (elevation-dependent weighting)

**inception_analysis_complete.R** — Main analysis script with eleven sections:

### Section 0: Setup
Package management, configuration, EA colour palette, output directories

### Section 1: Site metadata extraction
Query WISKI API for station metadata (coordinates, available parameters, date range)
- Outputs: Formatted table of station metadata

### Section 2a: Event data extraction  
Extract time-windowed hydrograph data for external software (PDM for PCs format)
- Single gauge, user-defined time window
- Outputs: CSV in PDM-compatible format (year, month, day, hour, minute, second, value columns)

### Section 2b: Weighted rainfall calculation
Combine multiple raingauge time series using Thiessen or custom weights
- Handles missing data via weight renormalisation
- API or WISKI export data sources
- Outputs: CSV in PDM-compatible format with weighted catchment-average rainfall

### Section 3: Top PT events extraction
Extract and rank performance testing events by magnitude
- Flow or stage events
- Seasonality analysis with polar plots (event magnitude vs time of year)
- Optional: export event hydrographs with time windows around peaks
- Outputs: Table of top N events, polar seasonality plot, optional event CSVs

### Section 4: Yearly time series plots
Multi-panel plots showing one panel per hydrological year
- Flow, level, or rainfall
- Optional threshold crossings
- Grid layout (default 3 columns)
- Outputs: Multi-panel PNG showing data across multiple years

### Section 5: Cumulative rainfall comparison
Compare cumulative rainfall across multiple gauges
- One plot per hydrological year
- Identifies periods of gauge disagreement
- Useful for data quality assessment
- Outputs: Multi-panel plot with shared legend

### Section 6: Double-mass plots
Validate rainfall data sources against each other
- Raingauge vs raingauge or raingauge vs radar (HYRAD)
- Cumulative totals with 1:1 reference line
- Detects systematic bias or period-specific drift
- Outputs: Double-mass plot PNG, CSV of input weights

### Section 7: Thiessen weight analysis
Spatial weighting for catchment-average rainfall (placeholder requiring configuration)
- Voronoi polygon generation from gauge coordinates
- Catchment boundary intersection
- Area-based weighting
- SAAR adjustment for elevation effects
- AAR calculation with standard errors
- Outputs: Thiessen weights table, SAAR vs AAR comparison table

### Section 8: Hypsometric curves
Elevation-dependent gauge weighting (placeholder requiring configuration)
- Plot catchment hypsometric curve (elevation vs area percentage)
- Calculate percentage of catchment above each gauge
- Derive elevation-dependent weights
- Optional: append to Thiessen weights from Section 7
- Outputs: Hypsometric curve plot with gauge positions, elevation weights table

### Section 9: Rating curve plotting
Multi-limb power-law rating equations with discontinuity analysis
- Plot multiple rating curves (e.g. IMRD vs WISKI vs consultant versions)
- Linear and log-log axes
- Calculate discontinuities at limb boundaries
- Solve for levels where limbs intersect
- Optional: overlay check gauging data
- Outputs: Rating curve plots (linear and log-log), discontinuity table, check gaugings table

### Section 10: Rated vs observed comparison
Validate rating equations against observed data
- Forward rating: level → flow
- Inverse rating: flow → level
- Difference time series (observed minus rated)
- Reference lines for QMED and thresholds
- Outputs: Two plots (rated vs observed flow, rated vs observed level)

Each section runs independently via Ctrl+Alt+T (RStudio).

Sections 7 and 8 are implementation-ready but require site-specific configuration (catchment shapefiles, SAAR rasters, gauge elevations). See original script for complete workflows.

## Governance adherence

The refactored code follows F&W data asset governance principles:

### Input validation
- All external-facing functions use checkmate assertions
- Type checking on parameters
- Range validation where appropriate
- Explicit NA handling documented

### Code documentation
- Heavy inline comments explaining logic and edge cases
- Roxygen-style function headers with parameters, returns, examples
- Mathematical derivations explained (rating equations, interpolation)
- Algorithm descriptions before complex blocks
- Regex patterns broken down character-by-character

### Naming conventions
- Consistent snake_case throughout functions and variables
- Parameters named meaningfully (gauge_elev not h_g)
- Exception: capital C retained in rating functions (hydraulics convention)
- No abbreviations except standard domain terms (AAR, SAAR, BNG)

### Data handling
- data.table operations retained (fastverse-aligned)
- Explicit return statements
- Temporary file cleanup documented
- Global variable assignments marked as compatibility requirements

### Structure
- Clear section breaks with visual separators
- Grouped by functional area
- File headers with dependencies, standards, authorship
- Version and modification date tracked

## Key changes from original

**Package management**
- Single vector for CRAN packages
- Version-pinned packages handled separately
- No more `require()` conditionals scattered throughout

**Functions**
- Extracted to separate file
- Heavy documentation added (roxygen headers, inline comments)
- Input validation via checkmate on all public functions
- Worked examples in documentation

**Variable naming**
- snake_case for functions and variables
- Follows data.table/fastverse conventions
- Rating parameters retain hydraulics convention (capital C)

**Structure**
- Configuration at top
- Analysis in clearly marked sections
- No globals buried mid-script
- Validation consolidated into blocks

**Code quality**
- Explicit returns throughout
- NA propagation explicit
- Edge cases documented
- Algorithm logic explained in comments

## Usage

```r
source("inception_functions_governed.R")

# Run entire script or individual sections via outline
# Jump to sections via dropdown (below code pane)
```

## Configuration points

### Section 1: Site metadata extraction
- `site_id`: WISKI station ID
- `measure`: "flow", "level", or "rainfall"
- `period`: time step in seconds (900 for 15-minute)
- `earliest_latest`: "earliest" or "latest" to get date range

### Section 2a: Event data extraction
- `site_id_event`: WISKI station ID
- `event_start`, `event_end`: date range (YYYY-MM-DD HH:MM:SS)
- `measure_event`: "flow", "level", or "rainfall"
- `output_format`: "PDMforPCs" or other for default CSV

### Section 2b: Weighted rainfall
- `raingauge_ids`: vector of WISKI IDs
- `weights`: numeric vector (should sum to ~1.0)
- `start_weighted`, `end_weighted`: date range
- `wiski_exports`: file paths or NA for API
- `model_name`: used in output filename

### Section 3: Top PT events
- `site_id_list_pt`: vector of WISKI IDs with "_FW" suffix
- `event_type`: "Flow" or "Stage"
- `n_events`: integer 1-54
- `output_event_data`: TRUE to export event hydrographs
- `window_hrs`: hours either side of peak for export

### Section 4: Yearly time series
- `site_id_list_yearly`: vector of WISKI IDs
- `measure_yearly`: "flow", "level", or "rainfall"
- `start_year`, `end_year`: hydrological years (Oct-Sep)
- `thresholds_yearly`: list of threshold vectors per site
- `wiski_exports_yearly`: file paths or NA for API

### Section 5: Cumulative rainfall
- `raingauge_ids_cumul`: vector of WISKI IDs
- `start_year_cumul`, `end_year_cumul`: hydrological years
- `catch_name_cumul`: catchment name for filename
- `wiski_exports_cumul`: file paths or NA for API

### Section 6: Double-mass plots
- `sources`: list(sourceX, sourceY) - "Raingauges" or "HYRAD"
- `raingauge_ids_dm`: list of ID vectors per source
- `raingauge_weights_dm`: list of weight vectors per source
- `read_files_dm`: list of file paths (NA for API, path for HYRAD CSV)
- `start_date_dm`, `end_date_dm`: date range (YYYY-MM-DD)
- `plot_title_dm`, `axes_names_dm`: labels for plot

### Section 7: Thiessen analysis (requires configuration)
- `raingauge_ids`: gauge list
- `catch_name`: catchment shapefile name (.shp)
- `readdir`: directory containing shapefile
- `saar_dataset_choice`: "SAAR 1961-90" or "SAAR 1981-2010"
- `use_api_for_coords`: TRUE/FALSE vector per gauge
- `rg_daily_data_files`: file paths for AAR calculation

### Section 8: Hypsometric curves (requires configuration)
- `dir`: directory for hypsometric CSV
- `read_file_name`: CSV with elevation histogram
- `catchment_name`: PDM catchment name
- `gauge_names`: vector of gauge names
- `gauge_elevations`: vector of elevations (mAOD)
- `append_to_weights_table`: TRUE to add to Section 7 output

### Section 9: Rating curves
- `upper_level_curves`, `c_param_curves`, `a_param_curves`, `b_param_curves`: 
  lists of parameter vectors per curve
- `legend_labels_curves`: list of curve names
- `qmed_curves`: QMED value for reference line (or NA)
- `thresholds_curves`: vector of threshold levels
- `max_level_to_plot`, `max_flow_to_plot`: axis limits
- `include_gaugings`: TRUE to overlay check gauging data
- `site_id_curves`: WISKI ID
- `site_name_curves`: descriptive name

### Section 10: Rated vs observed
- `site_id_rated`: WISKI ID
- `datetime_start_rated`, `datetime_end_rated`: date range
- `upper_level_rated`, `c_param_rated`, `a_param_rated`, `b_param_rated`: 
  rating parameter vectors
- `qmed_rated`: QMED for flow plot reference line
- `thresholds_rated`: threshold levels for level plot
- `wiski_export_level`, `wiski_export_flow`: file paths or NA for API

## Output control

```r
save_plots <- FALSE     # Toggle plot saving
tables_save_ext <- ".docx"  # .pdf, .png, or .docx
write_dir <- "./output/"
```

## Dependencies

**CRAN**
- data.table, ggplot2, dplyr, stringr, scales
- RcppRoll, magrittr, reshape2, cowplot
- jsonlite, rootSolve, afcolours, plotly, lubridate
- leaflet, tools, readr, checkmate

**Versioned**
- sf 1.0-15
- knitr 1.45
- rmarkdown 2.29
- gt 0.10.1

**GitHub**
- riskyData (JonPayneEA/riskyData)
- mappER (JonPayneEA/mappER)

## Notes

- Temporary file creation (temp_data.csv) handled by WISKI import function
- Global variable assignments retained in Thiessen functions for compatibility with existing workflows
- Rating discontinuities calculated using rootSolve::uniroot.all
- Hypsometric weights adjust automatically for duplicate elevations

## Testing recommendations

Before operational use:

1. **Function validation**: Run test cases on known data
   - WISKI import: verify temp_data.csv cleanup
   - Rating equations: check against manual calculations at limb boundaries
   - Thiessen weights: confirm sum to 1.0

2. **Output comparison**: Run parallel with original script
   - Compare numerical outputs (weights, ratings, AAR values)
   - Check plot aesthetics match EA standards
   - Verify table formatting in chosen save format

3. **Edge case testing**
   - Rating curves: test at limb boundaries and in gaps
   - AAR calculation: test with missing data (rescaled vs non-rescaled)
   - Thiessen polygons: test with gauges outside catchment boundary

4. **Performance**: Monitor for any slowdowns
   - data.table operations should be fast
   - checkmate validation adds minimal overhead
   - File I/O unchanged from original

## Version history

- v2.4 (2026-05-01): Experimental refactoring with governance adherence
- v2.3 (original): Monolithic analysis script
