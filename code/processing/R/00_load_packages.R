# ============================================================================ #
# 00_load_packages.R
# Purpose:  Check that every package the pipeline uses is installed, then attach
#           them. Sourced first by main.R; each later script starts with
#           rm(list = ls()), which clears objects but keeps the attached packages.
#           Nothing is installed here: the packages come from the 'bsat' conda
#           environment (setup/environment.yml) or from a manual install.
# Reads:    none
# Writes:   none
# Depends:  dplyr, tidyr, stringr, readr, readxl, openxlsx, zip, data.table, lfe,
#           ggplot2
# Notes:    stringr, data.table and ggplot2 are attached but no numbered script
#           currently calls them; lfe is used only by 23.
#           A missing or broken package stops the run with the list of names,
#           instead of a silent attempt to install from CRAN (which needs build
#           tools and can hang on locked-down machines).
# ============================================================================ #

bsat_packages <- c(
  "dplyr",        # Data manipulation
  "tidyr",        # Data reshaping
  "stringr",      # String operations
  "readr",        # Read/write CSV and text files
  "readxl",       # Read Excel (.xlsx, .xls)
  "openxlsx",     # Write Excel (.xlsx)
  "zip",          # Build the model input package (60_build_input_package.R)
  "data.table",   # Fast data manipulation
  "lfe",          # Linear fixed effects (23_compute_NTM_ave.R)
  "ggplot2"       # Data visualization
)

bsat_missing <- character(0)
for (bsat_pkg in bsat_packages) {
  ok <- tryCatch(suppressPackageStartupMessages(require(bsat_pkg, character.only = TRUE, quietly = TRUE)),
                 error = function(e) FALSE, warning = function(w) FALSE)
  if (!isTRUE(ok)) bsat_missing <- c(bsat_missing, bsat_pkg)
}
if (length(bsat_missing) > 0) {
  stop("R packages missing or failing to load: ", paste(bsat_missing, collapse = ", "),
       ". Install them into the 'bsat' environment (setup/environment.yml; rerun the bootstrap script) ",
       "or with install.packages(c(\"", paste(bsat_missing, collapse = "\", \""), "\")).")
}
cat("00_load_packages: attached", length(bsat_packages), "packages (R", paste0(R.version$major, ".", R.version$minor), ")\n")
rm(bsat_packages, bsat_missing, bsat_pkg, ok)
