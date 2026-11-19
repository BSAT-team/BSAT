# ============================================================================ #
# 22_compute_tariff_ave.R
# Purpose:  Compute region-commodity ad valorem import tariffs (simple average of
#           WITS MFN tariffs, latest reported year per product) and a zero
#           export-tax scaffold.
# Reads:    raw/trade_barriers/tariff_ave_WITS_2023.csv    (WITS TRAINS export: Reporter, Product, DutyType, Simple Average, Tariff Year)
#           raw/trade_barriers/country_code_WITS.xlsx      (columns country, ISO3, Reporter)
#           raw/mapping.csv
# Writes:   interim/tariff_ave_region.csv
#           interim/export_taxes_comm_reg.csv
# Depends:  openxlsx, dplyr, tidyr, readr (loaded by 00_load_packages.R)
# Notes:    HS codes are mapped to commodities by fixed 4- and 6-digit lists
#           (0201, 0202, 0207, 1001, 1003, 1005, 1006, 1007, 1201, 1507, 2304,
#           5201-5203, ...). Missing tariffs are set to 0 (with the current data:
#           all of Iraq, Saudi Arabia pork, Pakistan soybean oil). The EU is one
#           reporter (EUN). Export taxes are not observed and are 0 everywhere.
#           The year column of the tariff output is the string
#           "2023 (or last observed)".
# ============================================================================ #

# ---------------------------------------------------------------------------- #
# Set file paths
# ---------------------------------------------------------------------------- #

rm(list = ls())

# base path
# NOTE: base_dir is the 'data' folder, relative to the project root (main.R sets the working directory).
base_dir <- getOption("bsat.data_dir", file.path("..", "..", "data"))   # data root; set by main.R

# Input files
input_path_tariff       <-  file.path(base_dir, "raw", "trade_barriers/tariff_ave_WITS_2023.csv")
input_path_code         <-  file.path(base_dir, "raw", "trade_barriers/country_code_WITS.xlsx")
input_path_mapping      <-  file.path(base_dir, "raw", "mapping.csv")

# Output files
output_path_imp_tariff  <-  file.path(base_dir, "interim", "tariff_ave_region.csv")
output_path_exp_taxes   <-  file.path(base_dir, "interim", "export_taxes_comm_reg.csv")


# ---------------------------------------------------------------------------- #
# Load and clean WITS tariff data (2023 or latest)  
# ---------------------------------------------------------------------------- #
tariff_ave <- read.csv(input_path_tariff)                %>%
  filter(DutyType == "MFN")                              %>%
  select(Reporter, Product, Simple.Average, Tariff.Year) %>%
  rename(tariff_ave = Simple.Average)

country_code <- read.xlsx(input_path_code)


# ---------------------------------------------------------------------------- #
# Load baseline region mapping
# ---------------------------------------------------------------------------- #
mapping <- read_csv(input_path_mapping)                                          %>%
  filter(!country %in% c("Former Yemen North Sanaa", "Former Yemen South Aden")) %>%
  mutate(
    country_code = if_else(region_code == "EUR", "EUN",            country_code),
    country      = if_else(region_code == "EUR", "EUROPEAN UNION", country)
  ) %>%
  distinct()


# ---------------------------------------------------------------------------- #
# Merge region mapping with tariff data
# ---------------------------------------------------------------------------- #
tariff_ave <- tariff_ave                    %>%
  left_join(country_code, by = "Reporter")  %>%
  select(-Reporter, -country)               %>%
  mutate(ISO3 = ifelse(`ISO3` == "MMR", "BUR", `ISO3`))

tariff_ave_c <- mapping                     %>%
  left_join(tariff_ave, by = c("country_code" = "ISO3"))


# ---------------------------------------------------------------------------- #
# Format and classify HS codes to commodities
# ---------------------------------------------------------------------------- #
tariff_ave_c <- tariff_ave_c %>%
  mutate(
    Product = if_else(nchar(as.character(Product)) %in% c(3, 5),
                      paste0("0", Product),
                      as.character(Product)),
    commodity = case_when(
      Product %in% c("0201", "0202", "020610", "020621", "020622", "020629", "021020")             ~ "Beef and veal",
      Product %in% c("0207") ~ "Poultry",
      Product %in% c("0203", "020630", "020641", "020649", "020910", "021011", "021012", "021019") ~ "Pork",
      Product %in% c("1006") ~ "Rice",
      Product %in% c("1001") ~ "Wheat",
      Product %in% c("1005") ~ "Corn",
      Product %in% c("1003") ~ "Barley",
      Product %in% c("1007") ~ "Sorghum",
      Product %in% c("5201", "5202", "5203") ~ "Cotton",
      Product %in% c("1201") ~ "Soybeans",
      Product %in% c("2304") ~ "Soybean meal",
      Product %in% c("1507") ~ "Soybean oil",
      TRUE ~ NA
    )
  ) %>%
  filter(!is.na(commodity))


# ---------------------------------------------------------------------------- #
# Compute country-commodity level average tariff (simple average)
# ---------------------------------------------------------------------------- #
tariff_ave_c_k <- tariff_ave_c        %>%
  select(-group, region)              %>%
  group_by(region_code, region_name, country_code, country, Product, commodity, Tariff.Year) %>%
  summarise(tariff_ave_c_k = mean(tariff_ave, na.rm = TRUE), .groups = "drop")

# NOTE: Some tariffs are not available for all countries. The code then takes
#       the latest reported tariff from every country x product x year

tariffs <- tariff_ave_c_k         %>%
  filter(!is.na(tariff_ave_c_k))  %>%   
  group_by(
    region_code, region_name, country_code, country, Product, commodity
  )                               %>%
  slice_max(order_by = Tariff.Year, n = 1, with_ties = FALSE) %>%
  ungroup()                       %>%
  select(-Tariff.Year)            %>%
  group_by(region_code, region_name, country_code, country, commodity)             %>%
  summarise(tariff_ave_c_k = mean(tariff_ave_c_k, na.rm = TRUE), .groups = "drop") %>%
  group_by(region_code, region_name,                       commodity)              %>%
  summarise(tariff_ave_c_k = mean(tariff_ave_c_k, na.rm = TRUE), .groups = "drop")

# NOTE: dataframe "tariffs" collects all available data for import tariffs of 
#       commodities and regions included on the USDA baseline projections.
#       All missing tariffs are assumed equal to 0. Based on the current data, 
#       this implies that all import tariffs imposed by Iraq are assumed equal 
#       to zero, as well as the tariffs that Saudi Arabia imposes on Pork imports 
#       and Pakistan on soybean oil imports. 

commodities <- unique(tariffs$commodity)
tariffs_FN  <- mapping                   %>%
    select(region_code, region_name)     %>%
    unique()                             %>%
    expand_grid(commodity = commodities) %>%
    left_join(tariffs, by = c("region_code", "region_name", "commodity"))      %>%
    mutate(tariff_ave_c_k = if_else(is.na(tariff_ave_c_k), 0, tariff_ave_c_k),
           tariff_ave_c_k = tariff_ave_c_k/100
           ) %>%
    rename(value = tariff_ave_c_k)


# ---------------------------------------------------------------------------- #
# Import Tariffs - Final Adjustments
# ---------------------------------------------------------------------------- #
tariffs_FN <- tariffs_FN                    %>%    
  rename(region = region_code)              %>%
  mutate(
    commodity_name = commodity,
    commodity_name = case_when(
      commodity_name == "Soybean meal"  ~ "Soy Meal",
      commodity_name == "Soybean oil"   ~ "Soy Oil", 
      commodity_name == "Soybeans"      ~ "Soybean",
      TRUE                              ~ commodity_name
    ),
    commodity = case_when(
      commodity == "Beef and veal" ~ "Beef",
      commodity == "Soybean meal"  ~ "SoyMeal",
      commodity == "Soybean oil"   ~ "SoyOil",
      commodity == "Soybeans"      ~ "Soybean",
      TRUE                         ~ commodity      
    ),
    nest = case_when(
      commodity %in% c("Corn", "Sorghum")               ~ "Cereals",
      commodity %in% c("Beef", "Pork", "Poultry")       ~ "Livestock",
      commodity %in% c("SoyMeal", "SoyOil")             ~ "Secondary",
      commodity %in% c("Barley")                        ~ "Bly_Cereals",
      commodity %in% c("Wheat")                         ~ "Brd_Cereals",
      commodity %in% c("Cotton")                        ~ "Other",
      commodity %in% c("Rice")                          ~ "Rce_Cereals",
      commodity %in% c("Soybean")                       ~ "Soy_Cereals",
      TRUE                                              ~ NA_character_
    ),
    nest_name = case_when(
      nest == "Bly_Cereals" ~ "Barley Cereals",
      nest == "Livestock"   ~ "Livestock",
      nest == "Cereals"     ~ "Cereals",
      nest == "Other"       ~ "Other",
      nest == "Rce_Cereals" ~ "Rice Cereals",
      nest == "Secondary"   ~ "Soy related Secondary",
      nest == "Soy_Cereals" ~ "Soybean Cereals",
      nest == "Brd_Cereals" ~ "Bread Cereals",
      TRUE                  ~ NA_character_
    ),                              
    attribute             = "Import tariff",
    attribute_type        = "RYNC" ,
    attribute_description = "Ad valorem import tariff",
    unit                  = "decimal form",
    year                  = "2023 (or last observed)"
  )                              


# ---------------------------------------------------------------------------- #
# Exporting: import tariffs to CSV
# ---------------------------------------------------------------------------- #
write_csv(tariffs_FN, output_path_imp_tariff)


# ---------------------------------------------------------------------------- #
# Export Taxes
# ---------------------------------------------------------------------------- #

# NOTE: data on export taxes are not available for any region and commodity. Since 
#       export taxes may affect global markets, the model include them and assumed 
#       that they are equal to zero for all combinations of region x commodity 
#       in the benchmark scenario.

exp_tax_FN  <- mapping                      %>%
  select(region_code, region_name)          %>%
  unique()                                  %>%
  expand_grid(commodity = commodities)      %>%
  mutate(export_tax_c_k = 0  )              %>%
  rename(value = export_tax_c_k)

exp_tax_FN <- exp_tax_FN                    %>%    
  rename(region = region_code)              %>%
  mutate(
    commodity_name = commodity,
    commodity_name = case_when(
      commodity_name == "Soybean meal"  ~ "Soy Meal",
      commodity_name == "Soybean oil"   ~ "Soy Oil", 
      commodity_name == "Soybeans"      ~ "Soybean",
      TRUE                              ~ commodity_name
    ),
    commodity = case_when(
      commodity == "Beef and veal" ~ "Beef",
      commodity == "Soybean meal"  ~ "SoyMeal",
      commodity == "Soybean oil"   ~ "SoyOil",
      commodity == "Soybeans"      ~ "Soybean",
      TRUE                         ~ commodity      
    ),
    nest = case_when(
      commodity %in% c("Corn", "Sorghum")               ~ "Cereals",
      commodity %in% c("Beef", "Pork", "Poultry")       ~ "Livestock",
      commodity %in% c("SoyMeal", "SoyOil")             ~ "Secondary",
      commodity %in% c("Barley")                        ~ "Bly_Cereals",
      commodity %in% c("Wheat")                         ~ "Brd_Cereals",
      commodity %in% c("Cotton")                        ~ "Other",
      commodity %in% c("Rice")                          ~ "Rce_Cereals",
      commodity %in% c("Soybean")                       ~ "Soy_Cereals",
      TRUE                                              ~ NA_character_
    ),
    nest_name = case_when(
      nest == "Bly_Cereals" ~ "Barley Cereals",
      nest == "Livestock"   ~ "Livestock",
      nest == "Cereals"     ~ "Cereals",
      nest == "Other"       ~ "Other",
      nest == "Rce_Cereals" ~ "Rice Cereals",
      nest == "Secondary"   ~ "Soy related Secondary",
      nest == "Soy_Cereals" ~ "Soybean Cereals",
      nest == "Brd_Cereals" ~ "Bread Cereals",
      TRUE                  ~ NA_character_
    )  ,                              
    attribute             = "Export tax",
    attribute_type        = "RNC" ,
    attribute_description = "Ad valorem export tax",
    unit                  = "decimal form",
  )                              


# ---------------------------------------------------------------------------- #
# Exporting: export taxes to CSV
# ---------------------------------------------------------------------------- #
write_csv(exp_tax_FN, output_path_exp_taxes)


             
