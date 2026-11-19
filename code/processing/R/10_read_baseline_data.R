# ============================================================================ #
# 10_read_baseline_data.R
# Purpose:  Read the commodity sheets of the USDA International Long-Term
#           Projections workbook and reshape them into one long table
#           (commodity x region x year) holding the baseline variables.
# Reads:    raw/2025 International Long-Term Projections to 2034.xlsx   (one sheet per commodity, named as in commodity_list)
#           raw/region_commodity_list_2025.xlsx                         (sheet "Sheet1": region order within each sheet)
# Writes:   interim/baseline_projections_long.csv
# Depends:  openxlsx, dplyr, readr (loaded by 00_load_packages.R)
# Notes:    Source vintage constant: baseline_data <- "2025 International Long-Term
#           Projections to 2034.xlsx". The sheet layout is hard-coded: each region
#           block is 25 rows apart and 21 rows tall, starting at row 9 (Poultry) or
#           row 7 (all other commodities); the number and meaning of the columns per
#           commodity group (CL1..CL8) is fixed in the script; the regions of a sheet
#           are those of the region list, in order, followed by "World". The string
#           "     --" marks missing values; crop years "2025/26" keep the first year.
# ============================================================================ #

# ---------------------------------------------------------------------------- #
# Set file paths
# ---------------------------------------------------------------------------- #
 
rm(list = ls())

# base path
# NOTE: base_dir is the 'data' folder, relative to the project root (main.R sets the working directory).
base_dir <- getOption("bsat.data_dir", file.path("..", "..", "data"))   # data root; set by main.R

# Baseline projections excel file
# NOTE: baseline_data (below) is the USDA baseline projections workbook.
baseline_data        <- "2025 International Long-Term Projections to 2034.xlsx"             
   
# Input files
input_path_list      <- file.path(base_dir, "raw", "region_commodity_list_2025.xlsx")
input_path_bsl       <- file.path(base_dir, "raw", baseline_data)

# Output files
output_path_bsl_long <- file.path(base_dir, "interim", "baseline_projections_long.csv")

# ---------------------------------------------------------------------------- #
# Load region list and structure it by commodity
# ---------------------------------------------------------------------------- #

region_list     <- read.xlsx(input_path_list, sheet = "Sheet1")
commodity_split <- split(region_list, region_list$commodity)

# Construct region vectors (preserve Excel order + "World")
region_vectors <- list()
for (commodity_df in commodity_split) {
  regions <- unique(commodity_df$region)
  region_vectors[[commodity_df$commodity[1]]] <- c(regions, "World")
}

# ---------------------------------------------------------------------------- #
# Define commodity groups (for parsing rules)
# ---------------------------------------------------------------------------- #

CL1 <- c("Poultry")
CL2 <- c("Rice")
CL3 <- c("Cotton")
CL4 <- c("Barley", "Corn", "Sorghum", "Wheat")
CL5 <- c("Soybean meal")
CL6 <- c("Soybean oil")
CL7 <- c("Soybeans")
CL8 <- c("Beef and veal", "Pork")

commodity_list <- c(CL1, CL2, CL3, CL4, CL5, CL6, CL7, CL8)

# ---------------------------------------------------------------------------- #
# Read and reshape baseline data
# ---------------------------------------------------------------------------- #

# Initialize empty dataframe
# 18 variables in total
baseline <- data.frame(
  year            = NA, # crop year or calendar year
  area            = NA, # harvested area or crush (soymeal and soyoil)
  yield           = NA, # yield or extraction rate
  production      = NA, 
  imports         = NA,
  exports         = NA,
  total_cons      = NA, # total consumption
  
  # 3 types of food use
  food_only       = NA, # food use
  food_seed_ind   = NA, # food, seed, and industrial use
  food_other      = NA, # food and other use
  
  # 3 types of feed use
  feed_only       = NA, # feed use
  ind_feed_other  = NA, # industrial, feed, and other use
  feed_seed_waste = NA, # feed, seed, and waste
  
  crushing        = NA, # used for crushing (for Soybeans only)
  loss            = NA, # loss (for Cotton only)
  end_stock       = NA,
  region          = NA,
  commodity       = NA
)


for (commodity in commodity_list) {
  
  # Assign layout parameters by commodity group
  if (commodity %in% CL1) {
    col   <- 6
    names <- c("year", "production", "imports", "exports", "total_cons", "end_stock")
  } else if (commodity %in% CL2) {
    col   <- 8
    names <- c("year", "area", "yield", "production", "imports", "exports", "total_cons", "end_stock")
  } else if (commodity %in% CL3) {
    col   <- 9
    names <- c("year", "area", "yield", "production", "imports", "exports", "total_cons", "loss", "end_stock")
  } else if (commodity %in% CL4) {
    col   <- 10
    names <- c("year", "area", "yield", "production", "imports", "exports", "total_cons", "food_seed_ind", "feed_only", "end_stock")
  } else if (commodity %in% CL5) {
    col   <- 10
    names <- c("year", "area", "yield", "production", "imports", "exports", "total_cons", "food_other", "feed_only", "end_stock")
  } else if (commodity %in% CL6) {
    col   <- 10
    names <- c("year", "area", "yield", "production", "imports", "exports", "total_cons", "food_only", "ind_feed_other", "end_stock")
  } else if (commodity %in% CL7) {
    col   <- 11
    names <- c("year", "area", "yield", "production", "imports", "exports", "total_cons", "food_only", "feed_seed_waste", "crushing", "end_stock")
  } else if (commodity %in% CL8) {
    col   <- 6
    names <- c("year", "production", "imports", "exports", "total_cons", "end_stock")
  }  
  

  # Set initial row index by group
  if (commodity %in% CL1) {
    i <- 9; j <- 29
  } else {
    i <- 7; j <- 27
  }


  # Read each region's data
  for (r in region_vectors[[commodity]]) {
    single <- read.xlsx(input_path_bsl, sheet = commodity, rows = i:j, cols = 1:col)
    single <- mutate_all(single, as.character)
    names(single) <- names
    single$region <- r
    single$commodity <- commodity
    
    baseline <- bind_rows(baseline, single)
    i <- i + 25
    j <- j + 25
  }
}

# ---------------------------------------------------------------------------- #
# Clean and format data
# ---------------------------------------------------------------------------- #

baseline <- baseline                                  %>%
  filter(!if_all(everything(), is.na))                %>%
  mutate(across(everything(), ~na_if(.x, "     --"))) %>%
  mutate(year = sub("/.*", "", year))

tonum    <- c("year", "area", "yield", "production", "imports", "exports", "total_cons", "food_only",
           "food_seed_ind", "food_other", "feed_only", "ind_feed_other", "feed_seed_waste",
           "crushing", "loss", "end_stock")

baseline <- baseline                            %>%
  mutate_at(vars(all_of(tonum)), as.numeric)    %>%
  select(commodity, region, year, everything()) %>%
  arrange(commodity, region, year)

# ---------------------------------------------------------------------------- #
# Save output
# ---------------------------------------------------------------------------- #

write_csv(baseline, output_path_bsl_long, na = "")
