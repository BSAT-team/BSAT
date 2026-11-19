# ============================================================================ #
# 24_generate_data_exogenous.R
# Purpose:  Assemble data_exogenous.csv: calibrated parameters, 2025 international
#           prices, population and GDP per capita, unit price normalizations,
#           livestock inventory and slaughter, and the interim results of 20 to 23.
# Reads:    raw/exogenous_data.csv                        (calibrated elasticities and exogenous parameters, model schema)
#           raw/mapping.csv
#           raw/population_WB_2025.xls                    (sheet "Data", header on row 4, one column per year)
#           raw/population_IMF_WEO_2025.csv               (IMF WEO, Taiwan only)
#           raw/Current_GDP_WB_2025.xls                   (sheet "Data", header on row 4, one column per year)
#           raw/Current_GDP_IMF_WEO_2025.csv              (IMF WEO, Taiwan only)
#           raw/FAOSTAT_Livestock_Inventory_2024.csv      (Item, Year, Value; Area Code (ISO3))
#           raw/FAOSTAT_Slaughtered Livestock_2024.csv    (Item, Year, Value; Area Code (ISO3))
#           interim/international_prices_annual.csv       (from 20)
#           interim/ag_expenditure_shares.csv             (from 20)
#           interim/region_commodity_land_cost_shares.csv (from 21)
#           interim/tariff_ave_region.csv                 (from 22)
#           interim/export_taxes_comm_reg.csv             (from 22)
#           interim/NTM_IMP_ave_region.csv                (from 23, or the shipped interim copy)
#           interim/NTM_EXP_ave_region.csv                (from 23, or the shipped interim copy)
# Writes:   processed/data_exogenous.csv
# Depends:  dplyr, tidyr, readr, readxl (loaded by 00_load_packages.R)
# Notes:    Year constants are hard-coded: prices, population and GDP use 2025;
#           livestock inventory and slaughter use FAOSTAT Year == 2024. Population is
#           in 1,000 persons, GDP per capita in current USD. Prices become million
#           2017 USD per 1,000 native units (cotton: 1,000 480-lb bales). IMF WEO
#           files supply Taiwan only (COUNTRY == "Taiwan Province of China"; GDP in
#           billions, population in millions). FAOSTAT Item labels are matched by
#           name. "Land Unavailability" is renamed with a trailing space to match
#           the model. input_path_units (baseline_units.csv) is declared but not read.
# ============================================================================ #
   
# ---------------------------------------------------------------------------- #
# Set file paths
# ---------------------------------------------------------------------------- #

rm(list = ls())

# base path
# NOTE: base_dir is the 'data' folder, relative to the project root (main.R sets the working directory).
base_dir <- getOption("bsat.data_dir", file.path("..", "..", "data"))   # data root; set by main.R

# Input files
input_path_exo_params        <- file.path(base_dir,  "raw"    , "exogenous_data.csv")
input_path_intl_prices       <- file.path(base_dir,  "interim", "international_prices_annual.csv")
input_path_mapping           <- file.path(base_dir,  "raw"    , "mapping.csv")
input_path_units             <- file.path(base_dir,  "raw"    , "baseline_units.csv")
input_path_population_WB     <- file.path(base_dir,  "raw"    , "population_WB_2025.xls")
input_path_population_IMF    <- file.path(base_dir,  "raw"    , "population_IMF_WEO_2025.csv")
input_path_GDP_WB            <- file.path(base_dir,  "raw"    , "Current_GDP_WB_2025.xls")
input_path_GDP_IMF           <- file.path(base_dir,  "raw"    , "Current_GDP_IMF_WEO_2025.csv")
input_path_liv_inv           <- file.path(base_dir,  "raw"    , "FAOSTAT_Livestock_Inventory_2024.csv")
input_path_liv_slg           <- file.path(base_dir,  "raw"    , "FAOSTAT_Slaughtered Livestock_2024.csv")
input_path_ag_exp            <- file.path(base_dir,  "interim", "ag_expenditure_shares.csv")
input_path_land_cost_share   <- file.path(base_dir,  "interim", "region_commodity_land_cost_shares.csv")
input_path_imp_tariff        <- file.path(base_dir,  "interim", "tariff_ave_region.csv")
input_path_exp_taxes         <- file.path(base_dir,  "interim", "export_taxes_comm_reg.csv")
input_path_NTM_imp           <- file.path(base_dir,  "interim", "NTM_IMP_ave_region.csv")
input_path_NTM_exp           <- file.path(base_dir,  "interim", "NTM_EXP_ave_region.csv")


# Output files
output_path_data_exogenous <- file.path(base_dir, "processed", "data_exogenous.csv")               


# ---------------------------------------------------------------------------- #      
# Exogenous parameters
# ---------------------------------------------------------------------------- #
exo_params <- read_csv(input_path_exo_params) %>%
  mutate(attribute = case_when(
    attribute == "Land Unavailability" ~ "Land Unavailability ",
    TRUE ~ attribute
  ),
    attribute_description = case_when(
    attribute_description == "Land Unavailability" ~ "Land Unavailability ",
    TRUE ~ attribute_description
  ))


# ---------------------------------------------------------------------------- #
# International prices
# ---------------------------------------------------------------------------- #
intl_prices <- read_csv(input_path_intl_prices) %>%
  filter(marketing_year == 2025)                %>%
  rename(year = marketing_year)                 %>%
  mutate(commodity_name = commodity,
    commodity = case_when(
      commodity_name == "Beef and veal" ~ "Beef",
      commodity_name == "Soybean meal"  ~ "SoyMeal",
      commodity_name == "Soybean oil"   ~ "SoyOil",
      commodity_name == "Soybeans"      ~ "Soybean",
    TRUE ~ commodity_name
  ), 
    commodity_name = case_when(
      commodity == "SoyMeal" ~ "Soy Meal",
      commodity == "SoyOil"  ~ "Soy Oil",
      commodity == "Soybean" ~ "Soybean",
      commodity == "Beef"    ~ "Beef and veal",
      TRUE ~ commodity
    ),
    value = case_when(
    # convert the unit from USD cents/pound to Million USD/ 1,000 bales
    commodity == "Cotton"  ~ price * (1/100) * 480 * (1/1000),
    # convert the unit from USD cents/pound to Million USD/ 1,000 metric tons
    commodity == "Sorghum" ~ price * (1/100) * 2204.622 * (1/1000),
    # convert the unit from USD/metric ton to Million USD/ 1,000 metric tons
    TRUE                   ~ price * (1/1000)
  ),
  unit = case_when(
    commodity == "Cotton" ~ "USD Million (prices of 2017) / 1,000 bales",
    TRUE                  ~ "USD Million (prices of 2017) / 1,000 metric tons"
  )) %>%
  select(-price)


# Formatting
intl_prices <- intl_prices   %>%
  mutate(
    attribute = "International Price",
    attribute_description = "International Price",
    attribute_type = "YNC"
  )  %>%
  mutate(nest = case_when(
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
    nest == "Cereals"      ~ "Cereals",
    nest == "Livestock"    ~ "Livestock",
    nest == "Secondary"    ~ "Soy related Secondary",
    nest == "Bly_Cereals"  ~ "Barley Cereals",
    nest == "Brd_Cereals"  ~ "Bread Cereals",
    nest == "Other"        ~ "Other",
    nest == "Rce_Cereals"  ~ "Rice Cereals",
    nest == "Soy_Cereals"  ~ "Soybean Cereals"
  ))


# ---------------------------------------------------------------------------- #
# Population (1,000 habitants)
# ---------------------------------------------------------------------------- #  
mapping <- read_csv(input_path_mapping)     %>%
  select(group, region_code, country_code)  %>%
  unique()


# region name
region_name <- read_csv(input_path_mapping) %>%
  filter(group == "A")                      %>% 
  select(region_code, region_name)          %>%
  unique()                                  %>%
  rename(region = region_code)              %>%
  arrange(region)


# Data from World Bank
population_wide <- read_excel(input_path_population_WB, sheet = "Data", skip = 3) %>%
  select(
    -c(`Country Name`, `Indicator Name`, `Indicator Code`),
    -starts_with("...")
  ) %>%
  rename(country_code = `Country Code`) %>%
  mutate(country_code = ifelse(`country_code` == "MMR", "BUR", `country_code`))

population_long <- population_wide %>%
  pivot_longer(cols = -country_code, names_to = "year", values_to = "value") %>%
  # unit: 1,000 habitants
  mutate(value = value/1000)

# 2025 population
population <- population_long %>%
  filter(year == 2025 & country_code != "WLD")


# Taiwan - IMF data
population_IMF <- read_csv(input_path_population_IMF) %>%
  select(-DATASET,	-SERIES_CODE,	-OBS_MEASURE,	-INDICATOR,	-FREQUENCY,	-SCALE) %>%
  filter( COUNTRY == "Taiwan Province of China")      %>%
  mutate(country_code = "TWN")                        %>%  
  select(-COUNTRY)                                    %>%
  pivot_longer(cols = -country_code, names_to = "year", values_to = "value")    %>%
  mutate(
    value = as.numeric(value),
    # unit: 1,000 habitants
    value = value * 1000
  )

population_TWN <- population_IMF %>%
  filter(year == 2025 & country_code == "TWN")

# Append
population <- rbind(population, population_TWN)


# Aggregation
population_m <- mapping %>%
  left_join(population, by = c("country_code" = "country_code"))%>%
  # only keep the A group
  filter(group == "A")        %>% 
  select(-group)              %>%
  # NOTE: the leftjoin adds combinations region x country x year equal to NA.
  #       Those are countries with missing population data for 2025. They are 
  #       identified as those observation with year == NA. In order to avoid 
  #       generating an additional combination when year == NA in the subsequent 
  #       collapse, these observations are dropped.  
  filter(!is.na(year))        %>%
  group_by(region_code, year) %>%
  summarise(value = sum(value, na.rm = TRUE), .groups = "drop") %>%
  rename(region = region_code)


# ---------------------------------------------------------------------------- #
# GDP (USD current)
# ---------------------------------------------------------------------------- #  
GDP_long <- read_excel(input_path_GDP_WB, sheet = "Data", skip = 3) %>%
  select(`Country Code`, matches("^\\d+$")) %>%
  rename(country_code = `Country Code`)     %>%
  pivot_longer(cols = -country_code, names_to = "year", values_to = "value") %>%
  mutate(country_code = ifelse(`country_code` == "MMR", "BUR", `country_code`))

GDP <- GDP_long %>%
  filter(year == 2025 & country_code != "WLD")


# Taiwan - IMF data (USD billions, a billion has 9 zeros)
GDP_IMF <- read_csv(input_path_GDP_IMF) %>%
  select(-DATASET,	-SERIES_CODE,	-OBS_MEASURE,	-INDICATOR,	-FREQUENCY,	-SCALE) %>%
  filter( COUNTRY == "Taiwan Province of China")      %>%
  mutate(country_code = "TWN")                        %>%  
  select(-COUNTRY)                                    %>%
  pivot_longer(cols = -country_code, names_to = "year", values_to = "value")    %>%
  mutate(
    value = as.numeric(value),
    value = value * 1000000000
  )

GDP_TWN <- GDP_IMF %>%
  filter(year == 2025 & country_code == "TWN")

# Append
GDP <- rbind(GDP, GDP_TWN)


# ---------------------------------------------------------------------------- # 
# GDP per capita calculation using matched country coverage
# ---------------------------------------------------------------------------- # 
GDPpc <- mapping %>%
  filter(group == "A") %>%
  select(-group) %>%
  inner_join(GDP %>% rename(GDP = value), by = "country_code") %>%
  inner_join(
    population %>% rename(population = value),
    by = c("country_code", "year")
  ) %>%
  filter(!is.na(GDP), !is.na(population)) %>%
  group_by(region_code, year) %>%
  summarise(
    GDP = sum(GDP),
    population = sum(population),
    .groups = "drop"
  ) %>%
  transmute(
    region = region_code,
    year,
    value = GDP / (population * 1000)
  )


# ---------------------------------------------------------------------------- # 
# Formatting - GDP percapita & Population
# ---------------------------------------------------------------------------- # 
population <- population_m %>%
  mutate(
    attribute = "Population",
    unit = "1,000 habitants",
    attribute_type = "RY",
    attribute_description = "Population"
  ) %>%
  left_join(region_name, by = "region") %>%
  mutate(year = as.numeric(year))


GDPpc <- GDPpc %>%
  mutate(
    attribute = "GDP per capita",
    unit = "USD current per capita",
    attribute_type = "RY",
    attribute_description = "GDP per capita"
  ) %>%
  left_join(region_name, by = "region") %>%
  mutate(year = as.numeric(year))


# ---------------------------------------------------------------------------- #
# Normalized Prices to 1
# ---------------------------------------------------------------------------- #  
price_no_land <- region_name %>%
  mutate(attribute = "Price of No Land Input",
         value = 1,
         attribute_type = "R",
         attribute_description = "Price of No Land Input")


price_no_ag <- region_name %>%
  mutate(attribute = "Price of No AG",
         value = 1,
         attribute_type = "R",
         attribute_description = "Price of No Ag")


price_no_feed <- NULL
liv_comm      <- c("Beef and veal", "Pork", "Poultry")

  for (i in liv_comm) {
    temp <- region_name %>%
      mutate(
        commodity_name = i,
        attribute      = "P_NO_FEED",
        nest           = "Livestock",
        nest_name      = "Livestock",
        value          = 1,
        attribute_type = "RNC",
        attribute_description = "Price of Non-FEED products to produce livestock product"
      )
      price_no_feed <- bind_rows(price_no_feed, temp)
  }
      price_no_feed <- price_no_feed %>%
        mutate(commodity = commodity_name,
               commodity = case_when(
                  commodity_name == "Beef and veal" ~ "Beef",
                  TRUE ~ commodity_name       
        ))   

      
# ---------------------------------------------------------------------------- #
# Livestock Inventory
# ---------------------------------------------------------------------------- #  
Liv_inventory <- read_csv(input_path_liv_inv)                 %>%
  select(`Area Code (ISO3)`, `Item`, `Year`, `Unit`, `Value`) %>%
  filter(Item %in% c("Buffalo", "Cattle", "Chickens", "Ducks", "Geese", "Other birds", "Swine / pigs", "Turkeys")) %>%
  mutate(category = "",
         category = case_when(
           Item      %in% c("Buffalo", "Cattle")                                    ~ "Beef",
           Item      %in% c("Chickens", "Ducks", "Geese", "Other birds", "Turkeys") ~ "Poultry",
           Item      %in% c("Swine / pigs")                                         ~ "Pork",
         ),
         Value = case_when(
           # Units of Beef and Pork are animals, while of Poultry are 1,000 animals.
           # All values are converted to 1,000 animals
           category %in% c("Beef", "Pork")  ~ Value/1000,
           category %in% c("Poultry")       ~ Value,
         ))%>%                                                   
  rename(country_code = `Area Code (ISO3)`)  %>%      
  group_by(country_code, Year, category)     %>%
  summarise(value = sum(Value, na.rm = TRUE), .groups = "drop")

Liv_categories  <- unique(Liv_inventory$category)

Liv_inventory_m <- mapping               %>%
  mutate(Year = 2024)                    %>%
  expand_grid(category = Liv_categories) %>%
  left_join(Liv_inventory, by = c("country_code", "Year", "category")) %>%
  filter(group == "A")            %>% 
  select(-group)                  %>%
  # only keep the A group
  mutate(value = if_else(is.na(value), 0, value)) %>%
  group_by(region_code, category) %>%
  summarise(value = sum(value, na.rm = TRUE), .groups = "drop") %>%
  rename(region    = region_code) %>%
  rename(commodity = category )   %>%
  mutate(
    year           = 2024,
    nest           = "Livestock",
    nest_name      = "Livestock",
    commodity_name = case_when(
      commodity == "Beef"    ~ "Beef and veal",
      commodity == "Poultry" ~ "Poultry",
      commodity == "Pork"    ~ "Pork"
    ),
    attribute      ="inv_liv",
    attribute_type ="RYNC",
    attribute_description = "Inventory of livestock product k in region r",
    unit           ="1,000 animals"  
  ) %>%
  left_join(region_name, by = c("region" = "region"))


# ---------------------------------------------------------------------------- #
# Slaughtered Livestock 
# ---------------------------------------------------------------------------- #  
Liv_slaughter <- read_csv(input_path_liv_slg)                 %>%
  select(`Area Code (ISO3)`, `Item`, `Year`, `Unit`, `Value`) %>%
  # All available categories in variable `Item` match those used to calculate 
  # the livestock inventory. It is not necessary to filter the observations.
  mutate(category = "",
         category = case_when(
           Item      %in% c("Meat of buffalo, fresh or chilled", "Meat of cattle with the bone, fresh or chilled")                      ~ "Beef",
           Item      %in% c("Meat of chickens, fresh or chilled", "Meat of ducks, fresh or chilled", "Meat of geese, fresh or chilled", 
                            "Meat of pigeons and other birds n.e.c., fresh, chilled or frozen", "Meat of turkeys, fresh or chilled")    ~ "Poultry",
           Item      %in% c("Meat of pig with the bone, fresh or chilled")                                                              ~ "Pork",
         ),
         Value = case_when(
           # units of Beef and Pork are animals, while of Poultry are 1,000 animals.
           # All values are converted to 1,000 animals
           category %in% c("Beef", "Pork")  ~ Value/1000,
           category %in% c("Poultry")       ~ Value,
         ))                                  %>%                                                   
  rename(country_code = `Area Code (ISO3)`)  %>%      
  group_by(country_code, Year, category)     %>%
  summarise(value = sum(Value, na.rm = TRUE), .groups = "drop")


Liv_slaughter_m <- mapping               %>%
  mutate(Year = 2024)                    %>%
  expand_grid(category = Liv_categories) %>%  
  left_join(Liv_slaughter, by = c("country_code", "Year", "category")) %>%
  filter(group == "A")            %>% 
  select(-group)                  %>%
  mutate(value = if_else(is.na(value), 0, value)) %>%
  group_by(region_code, category) %>%
  summarise(value = sum(value, na.rm = TRUE), .groups = "drop") %>%
  rename(region    = region_code) %>%
  rename(commodity = category )   %>%
  mutate(
    year           = 2024,
    nest           = "Livestock",
    nest_name      = "Livestock",
    commodity_name = case_when(
      commodity == "Beef"    ~ "Beef and veal",
      commodity == "Poultry" ~ "Poultry",
      commodity == "Pork"    ~ "Pork"
    ),
    attribute      ="slt_liv",
    attribute_type ="RYNC",
    attribute_description = "Slaughter of livestock product k in every region r",
    unit           ="1,000 animals"  
  ) %>%
  left_join(region_name, by = c("region" = "region"))


# ---------------------------------------------------------------------------- #
# Loading additional data 
# ---------------------------------------------------------------------------- #  
AG_exp_shares   <- read.csv(input_path_ag_exp)            
Land_cst_shares <- read.csv(input_path_land_cost_share)   
Imp_tariffs     <- read.csv(input_path_imp_tariff)        
Exp_taxes       <- read.csv(input_path_exp_taxes)         
NTM_IMP         <- read.csv(input_path_NTM_imp)           
NTM_EXP         <- read.csv(input_path_NTM_exp)           


# ---------------------------------------------------------------------------- #
# Combine all data
# ---------------------------------------------------------------------------- #  
data_empty <- data.frame(
  region                = character(),
  year                  = numeric(),
  nest                  = character(),
  commodity             = character(),
  input                 = character(),
  attribute             = character(),
  value                 = numeric(),
  unit                  = character(),
  attribute_type        = character(),
  attribute_description = character(),
  region_name           = character(),
  nest_name             = character(),
  commodity_name        = character(),
  stringsAsFactors = FALSE
)

#NOTE: the type of variable "year" is change to "character"
#      in those data frames in which it is a numeric variable
#      to ensure allow appending the import tariff data frame.
#      Variable "year" in that data frame is a string.
data_empty$year       <- as.character(data_empty$year)
exo_params$year       <- as.character(exo_params$year)
intl_prices$year      <- as.character(intl_prices$year) 
GDPpc$year            <- as.character(GDPpc$year)
population$year       <- as.character(population$year)
Liv_inventory_m$year  <- as.character(Liv_inventory_m$year)
Liv_slaughter_m$year  <- as.character(Liv_slaughter_m$year)
AG_exp_shares$year    <- as.character(AG_exp_shares$year)           
Land_cst_shares$year  <- as.character(Land_cst_shares$year)    


data_exogenous <- bind_rows(
  data_empty, 
  exo_params,
  intl_prices, 
  GDPpc,
  population,
  price_no_land,
  price_no_ag,
  price_no_feed,
  Liv_inventory_m,
  Liv_slaughter_m,
  AG_exp_shares,           
  Land_cst_shares,    
  Imp_tariffs,             
  Exp_taxes,                
  NTM_IMP,                    
  NTM_EXP               
)


# ---------------------------------------------------------------------------- #  
# Save data_exogenous.csv
# ---------------------------------------------------------------------------- #  
write_csv(data_exogenous, output_path_data_exogenous, na = "")      


       
      
