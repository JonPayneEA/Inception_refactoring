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

**inception_analysis.R** — Main analysis script with ten sections
1. Setup: package management, configuration
2. Weighted rainfall: Thiessen polygons, AAR
3. PT event extraction: ranking, seasonality plots
4. Yearly time series: multi-year hydrographs
5. Cumulative rainfall: gauge comparisons
6. Double-mass plots: radar vs gauge validation
7. Thiessen weights: spatial analysis with SAAR adjustment
8. Hypsometric curves: elevation-dependent weighting
9. Rating curve plots: multi-limb equations, check gaugings
10. Rated vs observed: forward and inverse validation

Each section can be run independently with Ctrl+Alt+T (RStudio).

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

### Section 2: Weighted rainfall
- `raingauge_ids`: WISKI IDs
- `weights`: Thiessen weights or manual
- `start`, `end`: date range
- `wiski_exports`: file paths or NA for API

### Section 7: Thiessen analysis
- `raingauge_ids`: gauge list
- `readdir`, `catchment_file`: shapefile location
- `saar_dataset_choice`: "SAAR 1961-90" or "SAAR 1981-2010"

### Section 9: Rating curves
- `upper_level`, `c_param`, `a_param`, `b_param`: rating parameters per limb
- `legend_labels`: curve names
- `qmed`, `thresholds`: reference lines
- `include_gaugings`: overlay check gauging data

### Section 10: Rated vs observed
- `site_id`: WISKI ID
- `datetime_start`, `datetime_end`: date range
- `upper_level`, `c_param`, `a_param`, `b_param`: rating parameters
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
