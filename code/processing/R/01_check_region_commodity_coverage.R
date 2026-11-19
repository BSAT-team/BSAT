# ============================================================================ #
# 01_check_region_commodity_coverage.R
# Purpose:  Expand the region-commodity list of the USDA baseline to the full
#           region x commodity grid and flag the pairs the baseline does not cover.
# Reads:    raw/region_commodity_list_2025.xlsx      (sheet "Sheet1": columns region, commodity)
# Writes:   interim/region_commodity_coverage.csv
# Depends:  openxlsx, dplyr, tidyr, readr (loaded by 00_load_packages.R)
# Notes:    Audit only; no later script reads the output.
# ============================================================================ #

# ---------------------------------------------------------------------------- #   
# Set file paths
# ---------------------------------------------------------------------------- # 

rm(list = ls())

# base path
# NOTE: base_dir is the 'data' folder, relative to the project root (main.R sets the working directory).
base_dir <- getOption("bsat.data_dir", file.path("..", "..", "data"))   # data root; set by main.R

# Input files
input_path_list      <- file.path(base_dir, "raw", "region_commodity_list_2025.xlsx")

# Output files
output_path_coverage <- file.path(base_dir, "interim", "region_commodity_coverage.csv")

# ---------------------------------------------------------------------------- # 
# Load raw region-commodity mapping
# ---------------------------------------------------------------------------- # 

# r: region; k: commodity
rk <- read.xlsx(input_path_list, sheet = "Sheet1")  
rk <- rk %>% mutate(has_missing = 0)

# ---------------------------------------------------------------------------- # 
# Generate full region × commodity grid
# ---------------------------------------------------------------------------- # 

all_rk <- rk[, c("region", "commodity")] %>%
           complete(region, commodity)  

# ---------------------------------------------------------------------------- # 
# Flag missing observations
# ---------------------------------------------------------------------------- # 

merged_data <- left_join(all_rk, rk, by = c("region", "commodity")) %>%
  mutate_all(~ ifelse(is.na(.), 1, .))    %>%
  mutate(covered = 1 - has_missing)       %>%
  select(region, commodity, everything()) %>%
  arrange(region, commodity)

# ---------------------------------------------------------------------------- # 
# Export result
# ---------------------------------------------------------------------------- # 

write_csv(merged_data, output_path_coverage)
