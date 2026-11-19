# ============================================================================ #
# 60_build_input_package.R
# Purpose:  Bundle the four processed CSV files and a METADATA.csv into the
#           standard model input package (a zip with an Input/ folder) specified
#           in doc/data/data_specification.md. The shocks file holds neutral
#           values, so the package is the baseline package.
# Reads:    processed/data_params_init.csv
#           processed/data_exogenous.csv
#           processed/data_targets.csv
#           processed/data_shocks.csv
# Writes:   packages/baseline_<first year>_Input.zip     (first year = smallest year in data_targets.csv)
# Depends:  readr, dplyr, zip, tibble (loaded by 00_load_packages.R)
# Notes:    METADATA.csv records Author, Description, Comments and the build
#           timestamp. An existing zip with the same name is replaced.
# ============================================================================ #

rm(list = ls())
base_dir <- getOption("bsat.data_dir", file.path("..", "..", "data"))   # data root; set by main.R

files <- c("data_params_init.csv", "data_exogenous.csv", "data_targets.csv", "data_shocks.csv")
paths <- file.path(base_dir, "processed", files)
stopifnot(all(file.exists(paths)))

first_year <- read_csv(paths[3], col_types = cols(.default = col_character())) %>%
  pull(year) %>% as.integer() %>% min(na.rm = TRUE)

pkg_dir  <- file.path(base_dir, "packages")
zip_path <- file.path(pkg_dir, sprintf("baseline_%d_Input.zip", first_year))
dir.create(pkg_dir, showWarnings = FALSE, recursive = TRUE)

stage <- file.path(tempdir(), "bsat_package")
unlink(stage, recursive = TRUE)
dir.create(file.path(stage, "Input"), recursive = TRUE)
file.copy(paths, file.path(stage, "Input", files), overwrite = TRUE)

metadata <- tibble::tibble(
  field = c("Author", "Description", "Comments", "Pipeline build"),
  value = c("BSAT team", "Baseline scenario", "Neutral shocks: reproduces the USDA baseline",
            format(Sys.time(), "%Y-%m-%dT%H:%M:%S")))
write_csv(metadata, file.path(stage, "Input", "METADATA.csv"))

if (file.exists(zip_path)) unlink(zip_path)
zip::zip(normalizePath(zip_path, mustWork = FALSE), files = "Input", root = stage, mode = "mirror")
cat("60_build_input_package: wrote", zip_path, "\n")
