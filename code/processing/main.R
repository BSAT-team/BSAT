# ============================================================================ #
# main.R
# Purpose: Run the full data-processing pipeline for the 2025-2034 period.
#          Produces the four model-input files in data/processed/:
#          data_targets, data_exogenous, data_shocks, data_params_init.
# Run:     Rscript main.R   (from this folder)
# ============================================================================ #

# ---------------------------------------------------------------------------- #
# Set working directory to this file's location (code/processing/) so R/ resolves.
# ---------------------------------------------------------------------------- #
if (requireNamespace("rstudioapi", quietly = TRUE) &&
    rstudioapi::isAvailable()) {
  setwd(dirname(rstudioapi::getSourceEditorContext()$path))
} else {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grep("^--file=", args)])
  if (length(file_arg) == 1 && nzchar(file_arg)) {
    setwd(dirname(normalizePath(file_arg)))
  }
}

# Data root: <repo>/data (raw/, interim/, processed/). Scripts read it via getOption().
# Override with the BSAT_DATA_DIR environment variable if the data live elsewhere.
data_dir <- Sys.getenv("BSAT_DATA_DIR", unset = normalizePath(file.path("..", "..", "data"), mustWork = FALSE))
dir.create(file.path(data_dir, "interim"),   showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(data_dir, "processed"), showWarnings = FALSE, recursive = TRUE)
options(bsat.data_dir = data_dir, readr.show_col_types = FALSE, scipen = 999)
cat("Data directory:", data_dir, "\n")

# ---------------------------------------------------------------------------- #
# Load packages first, then source the numbered scripts in order. Each script
# begins with rm(list = ls()) (clears objects but keeps attached packages) and
# communicates only through files in data/interim and data/processed.
# ---------------------------------------------------------------------------- #
source("R/00_load_packages.R")

source("R/01_check_region_commodity_coverage.R")
source("R/10_read_baseline_data.R")
source("R/11_compute_feed_use_decomposition.R")
source("R/12_generate_data_targets.R")
source("R/20_compute_ag_expenditure_share.R")
source("R/21_compute_land_cost_share.R")
# Script 22 needs the WITS 2023 tariff extract, which is not distributed (UNCTAD TRAINS terms).
# Its derived outputs are shipped in data/interim and reused when the extract is absent.
tariff_raw <- file.path(getOption("bsat.data_dir"), "raw", "trade_barriers", "tariff_ave_WITS_2023.csv")
tariff_out <- file.path(getOption("bsat.data_dir"), "interim", c("tariff_ave_region.csv", "export_taxes_comm_reg.csv"))
if (file.exists(tariff_raw)) {
  source("R/22_compute_tariff_ave.R")
} else if (all(file.exists(tariff_out))) {
  cat("22_compute_tariff_ave: SKIPPED (WITS 2023 extract absent); reusing", paste(basename(tariff_out), collapse = " and "), "\n")
} else {
  stop("Script 22 needs ", basename(tariff_raw), " under data/raw/trade_barriers/ (see scripts/fetch_large_raw_data.sh), or the shipped interim results.")
}
# The NTM step needs raw files that are not distributed with the repository: two are too large,
# two are WITS extracts under UNCTAD TRAINS terms (see scripts/fetch_large_raw_data.*). Without
# them, the shipped interim NTM results are reused; without those either, the run stops here.
ntm_raw <- file.path(getOption("bsat.data_dir"), "raw", "trade_barriers",
                     c("BACI_HS92_Y2014_V202401b.csv", "tariff_ave_2014_WITS.csv", "ag_hs_products.csv"))
ntm_out <- file.path(getOption("bsat.data_dir"), "interim", c("NTM_IMP_ave_region.csv", "NTM_EXP_ave_region.csv"))
if (all(file.exists(ntm_raw))) {
  source("R/23_compute_NTM_ave.R")
} else if (all(file.exists(ntm_out))) {
  cat("23_compute_NTM_ave: SKIPPED (large raw files absent); reusing", paste(basename(ntm_out), collapse = " and "), "\n")
} else {
  stop("The NTM step needs ", paste(basename(ntm_raw), collapse = ", "),
       " under data/raw/trade_barriers/ (run scripts/fetch_large_raw_data.sh), or the interim results ",
       paste(basename(ntm_out), collapse = " and "), " under data/interim/. Neither was found.")
}
source("R/24_generate_data_exogenous.R")
source("R/30_generate_data_shocks.R")
source("R/40_generate_data_params_init.R")
# Script 50 runs last, right before packaging: it applies to data_targets.csv the same
# repairs the model would make on its own. Script 20 therefore computes the expenditure
# share from the unrepaired quantities of script 12, as the model authors do, and
# data_exogenous.csv stays identical to theirs.
source("R/50_harmonize_targets.R")
source("R/60_build_input_package.R")

cat("\n==== main.R (2025-2034): ALL DONE at",
    format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "====\n")
