# ============================================================================ #
# 30_generate_data_shocks.R
# Purpose:  Generate data_shocks.csv, a zero-filled scaffold of every shock
#           attribute for each region, commodity and year of the analysis period.
#           Levels live in data_exogenous.csv; this file holds the deviations.
# Reads:    raw/mapping.csv                 (the 42 model regions)
# Writes:   processed/data_shocks.csv
# Depends:  dplyr, tidyr, readr, tibble (loaded by 00_load_packages.R)
# Notes:    first_yr <- 2025 and last_yr <- 2034 define the horizon; keep first_yr
#           equal to lst_obsv_yr in 12_generate_data_targets.R. Ten shock attributes:
#           four trade barriers (all commodities), TFP value added and land
#           productivity (crops), TFP feed use (livestock), TFP intermediates
#           (SoyMeal, SoyOil), and two region-level shocks (ag expenditure share,
#           land supply). Two attribute names contain spaces. Editing these values
#           is how counterfactual scenarios are defined.
# ============================================================================ #

# ---------------------------------------------------------------------------- #
# Set file paths
# ---------------------------------------------------------------------------- #

rm(list = ls())

# base path
# NOTE: base_dir is the 'data' folder, relative to the project root (main.R sets the working directory).
base_dir <- getOption("bsat.data_dir", file.path("..", "..", "data"))   # data root; set by main.R

# Input files
input_path_mapping      <- file.path(base_dir, "raw", "mapping.csv")

# Output files
output_path_data_shocks <- file.path(base_dir, "processed", "data_shocks.csv")


# Analysis period: crop years 2025/26 .. 2034/35. The shock years are the first
# year of each crop year, i.e. 2025 .. 2034. Keep these in sync with the targets
# analysis period (lst_obsv_yr in 12_generate_data_targets.R) if the horizon moves.
first_yr  <-  2025
last_yr   <-  2034


# ---------------------------------------------------------------------------- #
# Regions, years, and commodity metadata
# ---------------------------------------------------------------------------- #

# 42 model regions (region code + name)
regions <- read_csv(input_path_mapping)       %>%
  distinct(region = region_code, region_name)

# Year horizon: the analysis period defined above.
years <- first_yr:last_yr

# Standard commodity -> nest / nest_name / commodity_name map (12 commodities)
commodity_meta <- tibble::tribble(
  ~commodity, ~commodity_name, ~nest,         ~nest_name,
  "Barley",   "Barley",        "Bly_Cereals", "Barley Cereals",
  "Wheat",    "Wheat",         "Brd_Cereals", "Bread Cereals",
  "Corn",     "Corn",          "Cereals",     "Cereals",
  "Sorghum",  "Sorghum",       "Cereals",     "Cereals",
  "Beef",     "Beef and veal", "Livestock",   "Livestock",
  "Pork",     "Pork",          "Livestock",   "Livestock",
  "Poultry",  "Poultry",       "Livestock",   "Livestock",
  "Cotton",   "Cotton",        "Other",       "Other",
  "Rice",     "Rice",          "Rce_Cereals", "Rice Cereals",
  "SoyMeal",  "Soy Meal",      "Secondary",   "Soy related Secondary",
  "SoyOil",   "Soy Oil",       "Secondary",   "Soy related Secondary",
  "Soybean",  "Soybean",       "Soy_Cereals", "Soybean Cereals"
)


# Commodity groups each shock applies to
all_comm   <- commodity_meta$commodity
crops      <- c("Barley", "Corn", "Cotton", "Rice", "Sorghum", "Soybean", "Wheat")
livestock  <- c("Beef", "Pork", "Poultry")
secondary  <- c("SoyMeal", "SoyOil")


# ---------------------------------------------------------------------------- #
# Builders (all shocks default to value = 0; unit = "decimal form")
# ---------------------------------------------------------------------------- #

# Commodity-level shock (attribute_type = "RYNC")
make_rync <- function(comms, attr, desc) {
  expand_grid(regions, year = years, commodity = comms) %>%
    left_join(commodity_meta, by = "commodity")         %>%
    mutate(
      input                 = NA_character_,
      attribute             = attr,
      value                 = 0,
      unit                  = "decimal form",
      attribute_type        = "RYNC",
      attribute_description = desc
    )
}

# Region-level shock (attribute_type = "RY")
make_ry <- function(attr, desc) {
  expand_grid(regions, year = years) %>%
    mutate(
      nest                  = NA_character_,
      commodity             = NA_character_,
      input                 = NA_character_,
      attribute             = attr,
      value                 = 0,
      unit                  = "decimal form",
      attribute_type        = "RY",
      attribute_description = desc,
      nest_name             = NA_character_,
      commodity_name        = NA_character_
    )
}


# ---------------------------------------------------------------------------- #
# Assemble all shock blocks
# ---------------------------------------------------------------------------- #       

data_shocks <- bind_rows(
  # Trade barriers (all commodities)
  make_rync(all_comm, "shock_import_tariff",
            "Shock to ad valorem import tariff (Percentage Points)"),
  make_rync(all_comm, "shock_export_tax",
            "Shock to ad valorem export tax (Percentage Points)"),
  make_rync(all_comm, "shock_nontariff_import",
            "Shock to Non Tariff Measure for importing a product (Percentage Points)"),
  make_rync(all_comm, "shock_nontax_export",
            "Shock to Non Tax Measure for exporting a product (Percentage Points)"),

  # TFP productivity and land (crops)
  make_rync(crops, "shock TFP Productivity Value Added",
            "Shock to TFP Productivity Value Added (Percentage Points)"),
  make_rync(crops, "shock_land_prod",
            "Shock to Land Productivity (Percentage change)"),

  # TFP productivity of feed use (livestock)
  make_rync(livestock, "shock_TFP_Productivity_Feed_Use_livestock",
            "Shock to TFP Productivity of Feed Use in the production of livestock (Percentage Points)"),

  # TFP productivity of intermediates (secondary / soy products)
  make_rync(secondary, "shock TFP Productivity Intermediates",
            "Shock to TFP Productivity Intermediates (Percentage Points)"),

  # Region-level shocks
  make_ry("shock_ag_expenditure_share",
          "Shock to Ag Expenditure Share (percentage change)"),
  make_ry("shock_land_supply",
          "Shock to Land Supply Availability (Percentage change)")
) %>%
  select(region, year, nest, commodity, input, attribute, value, unit,
         attribute_type, attribute_description, region_name, nest_name,
         commodity_name) %>%
  arrange(attribute, region, commodity, year)

# ---------------------------------------------------------------------------- #
# Save data_shocks.csv
# ---------------------------------------------------------------------------- #

write_csv(data_shocks, output_path_data_shocks, na = "")      


