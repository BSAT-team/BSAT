# ============================================================================ #
# 11_compute_feed_use_decomposition.R
# Purpose:  Split each region's total feed use of every feed crop across the three
#           livestock products (beef, pork, poultry) in proportion to FAOSTAT
#           livestock value-of-production shares.
# Reads:    raw/mapping.csv
#           raw/FAOSTAT_total_livestock_value_constant_IntlD.csv   (2015 total livestock value, constant 2014-2016 I$)
#           raw/FAOSTAT_each_livestock_value_constant_IntlD.csv    (2015 value by livestock item, indigenous meat)
#           interim/baseline_projections_long.csv                  (from 10_read_baseline_data.R)
# Writes:   interim/livestock_value_shares.xlsx
#           interim/feed_use_decomposition.xlsx
# Depends:  dplyr, tidyr, readr, openxlsx (loaded by 00_load_packages.R)
# Notes:    Z_k = feed_only + ind_feed_other + feed_seed_waste for Barley, Corn,
#           Sorghum, Soybeans, Soybean meal, Soybean oil and Wheat; Z_ik = Z_k x value
#           share of livestock i. A missing value share is read as no demand (set to
#           0). Beef is cattle plus buffalo meat. FAOSTAT column
#           "Area Code (ISO3)" and the five "(indigenous)" Item labels are
#           matched by name; Myanmar is recoded MMR -> BUR. Only group A regions
#           and years >= 2025 are kept.
# ============================================================================ #

# ---------------------------------------------------------------------------- #
# Set file paths
# ---------------------------------------------------------------------------- #   

rm(list = ls())

# base path
# NOTE: base_dir is the 'data' folder, relative to the project root (main.R sets the working directory).
# 'last observed' = the year of the last observed data in the baseline projections.
base_dir <- getOption("bsat.data_dir", file.path("..", "..", "data"))   # data root; set by main.R

# Input files
input_path_mapping            <- file.path(base_dir, "raw", "mapping.csv")
input_path_baseline           <- file.path(base_dir, "interim", "baseline_projections_long.csv")
input_path_total_value        <- file.path(base_dir, "raw", "FAOSTAT_total_livestock_value_constant_IntlD.csv")
input_path_each_value         <- file.path(base_dir, "raw", "FAOSTAT_each_livestock_value_constant_IntlD.csv")

# Output files
output_path_value_share       <- file.path(base_dir, "interim", "livestock_value_shares.xlsx")
output_path_results           <- file.path(base_dir, "interim", "feed_use_decomposition.xlsx")


# ---------------------------------------------------------------------------- #
# Value shares as proxy for feed use shares (FAOSTAT, 2015)
# To replace animal unit shares
# ---------------------------------------------------------------------------- #      

# Note:
# - Source: FAOSTAT
# - Use 2015 livestock value of production (total and for each livestock type)
# - Based on constant 2014–2016 prices (I$)
# - Indigenous meat only


# Load total livestock value
total_livestock_value_c <- read.csv(input_path_total_value) %>% 
  select(c("Area.Code..ISO3.", "Value"))                    %>%
  rename(ISO3 = Area.Code..ISO3., total_value = Value)      %>%
  mutate(ISO3 = ifelse(`ISO3` == "MMR", "BUR", `ISO3`))


# Load value by livestock type
each_livestock_value_c <- read.csv(input_path_each_value)   %>%
  filter(Item %in% c(
    "Meat of cattle with the bone, fresh or chilled (indigenous)",
    "Meat of buffalo, fresh or chilled (indigenous)",
    "Meat of pig with the bone, fresh or chilled (indigenous)",
    "Meat of chickens, fresh or chilled (indigenous)",
    "Meat of turkeys, fresh or chilled (indigenous)")
  )                                                         %>%
  mutate(commodity = case_when(
    Item %in% c("Meat of cattle with the bone, fresh or chilled (indigenous)", "Meat of buffalo, fresh or chilled (indigenous)") ~ "Beef and veal",
    Item == "Meat of pig with the bone, fresh or chilled (indigenous)"    ~ "Pork",
    Item %in% c("Meat of chickens, fresh or chilled (indigenous)", "Meat of turkeys, fresh or chilled (indigenous)") ~ "Poultry"
  )) %>%
  select(c("Area.Code..ISO3.", "Value", "commodity"))       %>%
  rename(ISO3 = Area.Code..ISO3.)                           %>% 
  mutate(ISO3 = ifelse(`ISO3` == "MMR", "BUR", `ISO3`))     %>%
  group_by(ISO3, commodity) %>%
  summarise(value_l = sum(Value, na.rm = TRUE), .groups = "drop")


# Aggregate livestock value by region and compute value shares
# ---------------------------------------------------------------------------- #

# Region-level livestock value
mapping <- read_csv(input_path_mapping)  %>%
  filter(!country %in% c("Former Yemen North Sanaa", "Former Yemen South Aden"))


livestock_values <- mapping                                           %>%
  left_join(each_livestock_value_c,  by = c("country_code" = "ISO3")) %>%
  left_join(total_livestock_value_c, by = c("country_code" = "ISO3")) %>%
  group_by(group, region_code, region, commodity) %>%
  summarise(
    value_l     = sum(value_l,     na.rm = TRUE),
    total_value = sum(total_value, na.rm = TRUE),
    .groups = "drop"
  )                                                                   %>%
  filter(!is.na(commodity))


# Match region-level projections and compute value shares
region_livestock <- read_csv(input_path_baseline)              %>%
  select(region, commodity)                                    %>%
  filter(commodity %in% c("Beef and veal", "Pork", "Poultry")) %>%
  arrange(region, commodity)                                   %>%
  distinct()


region_livestock_value <- region_livestock                     %>% 
  left_join(livestock_values, by = c("region", "commodity"))   %>%
  filter(region != "World" & group == "A" )                    %>%
  select(-group)


# Compute value shares
value_shares <- region_livestock_value        %>%
  mutate(value_share = value_l / total_value) %>%
  select(region, commodity, value_share)


# Export value shares
write.xlsx(value_shares, file = output_path_value_share)



# Drop intermediate objects
drop_objects <- c("each_livestock_value_c", "livestock_values", "region_livestock",
                  "region_livestock_value", "total_livestock_value_c")

rm(list = drop_objects)


# ---------------------------------------------------------------------------- #
# Crops: Feed Use of 7 Crops
# - Barley, Corn, Sorghum, SoyMeal, SoyOil, Soybeans, Wheat
# - Notation: k = crop, i = livestock, Z_k = feed use of crop k
# ---------------------------------------------------------------------------- #

group <- mapping                                  %>%
  select(group, region_code, region, region_name) %>%
  distinct()

baseline    <- read_csv(input_path_baseline)

crops       <- baseline                 %>%
  left_join(group, by = "region")       %>%
  filter(!commodity %in% c("Beef and veal", "Pork", "Poultry", "Cotton", "Rice"))                              %>%
  select(commodity, group, region_code, region, region_name, year, feed_only, ind_feed_other, feed_seed_waste) %>%
  mutate(feed_use = rowSums(select(., feed_only, ind_feed_other, feed_seed_waste), na.rm = TRUE))              %>%
  select(-feed_only, -ind_feed_other, -feed_seed_waste) %>%
  rename(Z_k = feed_use) %>%
  filter(group == "A")   %>%
  select(-group)


# ---------------------------------------------------------------------------- #
# Infer Z_ik: Feed Use of Crop k for Livestock i
# ---------------------------------------------------------------------------- #

# Livestock categories
ls <- c("Beef and veal", "Pork", "Poultry")

# Create all combinations of (region, year, crop, livestock)
Z_ik <- crops                       %>%
  filter(year >= 2025)              %>%
  distinct(region, year, commodity) %>%
  cross_join(
    expand_grid(
      livestock = ls
    )
  )


# Merge with crop data
Z_ik <- left_join(Z_ik, crops, by = c("region", "year", "commodity"))


# Merge with value shares
Z_ik             <- left_join(Z_ik, value_shares, by = c("region", "livestock" = "commodity"))
Z_ik$value_share <- if_else(is.na(Z_ik$value_share), 0, Z_ik$value_share)
#IMPORTANT: we assume that any missing value share is a signal of no demand. 
#           Consequently, all missing value shares are converted to zero.


# ---------------------------------------------------------------------------- #
# Compute Z_ik
# - Z_ik = Z_k × value_share
# ---------------------------------------------------------------------------- #

results <- Z_ik     %>%
    select(-region) %>%
    rename(input     = commodity)       %>%
    rename(commodity = livestock)       %>%
    rename(region    = region_code)     %>%
  mutate(
    commodity_name = commodity,
    commodity      = case_when(
      commodity == "Beef and veal" ~ "Beef",
      TRUE                         ~ commodity
      ),
    nest = case_when(
      commodity %in% c("Beef", "Pork", "Poultry")       ~ "Livestock",
      TRUE                                              ~ NA_character_
      ),
    nest_name = case_when(
      nest == "Livestock"   ~ "Livestock",
      TRUE                  ~ NA_character_
      ),
      value                 = Z_k * value_share ,
      attribute             = "Total_feed_use_input_to_commodity",
      unit                  = "1,000 metric tones", 
      attribute_type        = "RYNCI",
      attribute_description = "Total Feed Use of Input to produce livestock commodity",
      input = case_when(
        input == "Soybean meal" ~ "SoyMeal",
        input == "Soybean oil"  ~ "SoyOil",
        input == "Soybeans"     ~ "Soybean",
        TRUE                    ~ input
        )) %>%
  select(region, year, nest, commodity, input, attribute, value, Z_k, value_share, unit, 
         attribute_type, attribute_description, region_name, nest_name, commodity_name) %>%
  arrange(region, year, commodity, attribute)  


# ---------------------------------------------------------------------------- #
# Save final results
# ---------------------------------------------------------------------------- #
write.xlsx(results, file = output_path_results)   

    

         