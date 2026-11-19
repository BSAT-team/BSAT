# ============================================================================ #
# 20_compute_ag_expenditure_share.R
# Purpose:  Compute the agricultural expenditure share (spending on the twelve
#           modeled commodities as a percentage of real GDP) by region for 2025,
#           and save the annual international price series built along the way.
# Reads:    processed/data_targets.csv                                     (from 12, before harmonization: food and feed quantities)
#           raw/2026-06-19 IMF Commodity Prices external-data.xlsx        (sheet "External": monthly, nine non-meat commodities)
#           raw/2026-06-19 International Prices FAO Meat.xlsx             (sheet "data": monthly export prices, beef, pork, poultry)
#           raw/2026-06-24 CPI_US.xlsx                                    (sheet "Sheet1": columns year, CPI_2017)
#           raw/Global GDP Shares and GDP Growth Assumptions to 2035.xlsx  (first sheet: USDA real GDP levels and growth)
#           raw/mapping.csv
# Writes:   interim/international_prices_annual.csv     (marketing-year averages, native units, all years)
#           interim/ag_expenditure_shares.csv
# Depends:  openxlsx, dplyr, tidyr, readr (loaded by 00_load_packages.R)
# Notes:    IMF series are picked by the code in row 1 (imf_meta: PBARL, PWHEAMT,
#           PCOTTIND, PRICENPQ, PMAIZMT, PSORG, PSOYB, PSMEA, PSOIL); dates are the
#           "YYYYMm" labels in column 1. FAO meat prices are simple averages of fixed
#           column positions (cols 3-5 beef, 6/8/9 pork, 7/10 poultry; dates
#           "MM/DD/YYYY" in col 2). Prices are deflated to 2017 USD with CPI_2017 and
#           averaged over USDA marketing years (start_mo); an incomplete last year
#           uses the last 12 observed months. The GDP workbook is read by position
#           (col 2 = 2025 level, cols 6-10 = growth 2025-2029, col 13 = 2026-35
#           average) and its region labels must match xwalk plus the OAO and ONA
#           residual definitions. Only year 2025 is exported.
# ============================================================================ #


# ---------------------------------------------------------------------------- #
# Set file paths
# ---------------------------------------------------------------------------- #

rm(list = ls())

# base path
# NOTE: base_dir is the 'data' folder, relative to the project root (main.R sets the working directory).
base_dir <- getOption("bsat.data_dir", file.path("..", "..", "data"))   # data root; set by main.R

# Input files
input_path_data_targets <- file.path(base_dir, "processed", "data_targets.csv")

# International prices are read directly from the raw IMF + FAO downloads.
input_path_imf          <- file.path(base_dir, "raw", "2026-06-19 IMF Commodity Prices external-data.xlsx")
input_path_fao          <- file.path(base_dir, "raw", "2026-06-19 International Prices FAO Meat.xlsx")
input_path_gdp          <- file.path(base_dir, "raw", "Global GDP Shares and GDP Growth Assumptions to 2035.xlsx")
input_path_cpi_17       <- file.path(base_dir, "raw", "2026-06-24 CPI_US.xlsx")
input_path_mapping      <- file.path(base_dir, "raw", "mapping.csv")

# Output files
output_path_intl_annual <- file.path(base_dir, "interim", "international_prices_annual.csv")        
ouput_path_ag_exp       <- file.path(base_dir, "interim", "ag_expenditure_shares.csv")


# ---------------------------------------------------------------------------- #
# Numerator: real food expenditure (billion USD, constant 2017 prices)
# ---------------------------------------------------------------------------- #

# International prices read directly from the raw IMF + FAO files. IMF supplies 
# the nine non-meat commodities (one column each, picked by code); FAO supplies 
# the three meats as a simple average of the available country export-price 
# series. All monthly prices are deflated using the annual average U.S. CPI 
# (base year: 2017 = 1). Subsequently, the resulting prices are converted to 
# Million USD per 1,000 of its native quantity unit so the price matches the 
# data_targets quantities (1,000 mt, except Cotton in 1,000 480-lb bales).

# IMF column code -> model commodity and marketing-year start month
#   (meats start in Jan; Barley/Wheat Jun; Cotton/Rice Aug;
#    Corn/Sorghum/Soybean Sep; SoyMeal/SoyOil Oct)
imf_meta <- data.frame(
  code      = c("PBARL","PWHEAMT","PCOTTIND","PRICENPQ","PMAIZMT","PSORG","PSOYB","PSMEA","PSOIL"),
  commodity = c("Barley","Wheat","Cotton","Rice","Corn","Sorghum","Soybean","SoyMeal","SoyOil"),
  start_mo  = c(6L, 6L, 8L, 8L, 9L, 9L, 9L, 10L, 10L),
  stringsAsFactors = FALSE)


# IMF monthly series for the nine non-meat commodities
imf_raw     <-  read.xlsx(input_path_imf, sheet = "External", colNames = FALSE)
imf_code    <-  as.character(unlist(imf_raw[1, ]))      # row 1 = commodity code
imf_lab     <-  trimws(as.character(imf_raw[[1]]))      # col 1 = date label "YYYYMm"
drow        <-  grepl("^[0-9]{4}M[0-9]+$", imf_lab)     # data rows only
imf_year    <-  as.integer(sub("M.*$", "", imf_lab))
imf_month   <-  as.integer(sub("^.*M", "", imf_lab))
imf_monthly <-  bind_rows(lapply(seq_len(nrow(imf_meta)), function(i) {
  j <- match(imf_meta$code[i], imf_code)
  data.frame(commodity = imf_meta$commodity[i], 
             year      = imf_year[drow],
             month     = imf_month[drow],
             price     = suppressWarnings(as.numeric(imf_raw[[j]][drow])))
}))


# FAO monthly meat prices: simple average of the country export series per meat
#   cols 3 US / 4 Australia / 5 Brazil = Beef; 6 Brazil / 8 EU / 9 US = Pork;
#        7 Brazil / 10 US = Poultry
fao_raw     <- read.xlsx(input_path_fao, sheet = "data", colNames = FALSE)
fao_lab     <- trimws(as.character(fao_raw[[2]]))      # col 2 = date "MM/DD/YYYY"
drf         <- grepl("^[0-9]{2}/[0-9]{2}/[0-9]{4}$", fao_lab)
fao_month   <- as.integer(substr(fao_lab, 1, 2))
fao_year    <- as.integer(substr(fao_lab, 7, 10))
fcol        <- function(j) suppressWarnings(as.numeric(fao_raw[[j]][drf]))
fao_monthly <- bind_rows(
  data.frame(commodity = "Beef",    
             year      = fao_year[drf], 
             month     = fao_month[drf],
             price     = rowMeans(cbind(fcol(3), fcol(4), fcol(5)), na.rm = TRUE)),
  
  data.frame(commodity = "Pork",    
             year      = fao_year[drf], 
             month     = fao_month[drf],
             price     = rowMeans(cbind(fcol(6), fcol(8), fcol(9)), na.rm = TRUE)),
  
  data.frame(commodity = "Poultry", 
             year      = fao_year[drf], 
             month     = fao_month[drf],
             price     = rowMeans(cbind(fcol(7), fcol(10)), na.rm = TRUE)))


# Assign each monthly observation to its USDA marketing year (the year Y whose
# window starts in month start_mo), then average to an annual price. In order
# to keep the seasonality, we calculate the 12 month average across all prices.
# The average price of the last year is specifically calculated as the average 
# of the observed price of the last 12 months for which price data is available 

start_lk <- bind_rows(imf_meta[c("commodity", "start_mo")],
                      data.frame(commodity = c("Beef", "Pork", "Poultry"), start_mo = 1L))

cpi_17   <-  read.xlsx(input_path_cpi_17, sheet = "Sheet1")


#) All monthly prices
df_prices <- bind_rows(imf_monthly, fao_monthly) %>%
  left_join(cpi_17,    by = "year")              %>%
  inner_join(start_lk, by = "commodity")         %>%
  mutate(price = price / CPI_2017,
         mi    = year * 12 + (month - 1),
         marketing_year = (mi - (start_mo - 1)) %/% 12)

#) Average annual prices
annual <- df_prices                   %>%
  group_by(commodity, marketing_year) %>%
  summarise(n_obs = sum(!is.na(price)),
            price = mean(price, na.rm = TRUE),
            .groups = "drop")

#) Last 12 months available prices for each commodity 
last12_prices <- df_prices   %>%
  group_by(commodity)        %>%
  arrange(mi)                %>%
  filter(!is.na(price))      %>%
  slice_tail(n = 12)         %>%
  summarise(price_last12 = mean(price),
                 .groups = "drop")

last_year_prices <- df_prices %>%
  group_by(commodity)         %>%
  summarise(marketing_year = max(marketing_year),
            .groups = "drop")         %>%
  left_join(last12_prices, by = "commodity")

annual_native <- annual       %>%
  left_join(last_year_prices, by = c("commodity", "marketing_year")) %>%
  mutate( price = if_else(n_obs < 12, price_last12, price))          %>%
  select(-price_last12, -n_obs)

# Save the full multi-year annual series (native units, USDA-style names) so any
# base year can be selected downstream; same schema as the previous file.
usda_name <- c(Barley  = "Barley", 
               Wheat   = "Wheat", 
               Cotton  = "Cotton", 
               Rice    = "Rice",
               Corn    = "Corn", 
               Sorghum = "Sorghum", 
               Soybean = "Soybeans",
               SoyMeal = "Soybean meal", 
               SoyOil  = "Soybean oil",
               Beef    = "Beef and veal", 
               Pork    = "Pork", 
               Poultry = "Poultry")

annual_native                                      %>%
  mutate(unit      = if_else(commodity %in% c("Cotton", "Sorghum"), "US cents/pound", "USD/metric tonne"),
         commodity = unname(usda_name[commodity])) %>%
  select(commodity, marketing_year, price, unit)   %>%
  arrange(commodity, marketing_year)               %>%
  write_csv(output_path_intl_annual, na = "")


# Prices are converted to Million USD per 1,000 of each commodity's native
# quantity unit so they match the data_targets quantities.
price_base <- annual_native                  %>%
  mutate(price_conv = case_when(
    commodity == "Cotton"  ~ price * (1 / 100) * 480      * (1 / 1000),  # cents/lb, qty 1,000 bales
    commodity == "Sorghum" ~ price * (1 / 100) * 2204.622 * (1 / 1000),  # cents/lb, qty 1,000 mt
    TRUE                   ~ price * (1 / 1000)                          # USD/mt,   qty 1,000 mt
  )) %>%
  select(commodity, marketing_year, price_conv)


# Domestic-use quantities by region, commodity and year (multi-year): food
# consumption plus feed_other, where feed_other = total feed use minus the feed
# used to produce the three modeled livestock. data_targets already carries both
# the total feed use ("Feed Consumption") and the feed-to-livestock decomposition
# ("Total Feed Use of Input to produce livestock commodity", = Z_ik).
dt         <- read.csv(input_path_data_targets)

food       <- dt                                      %>% 
  filter(attribute_description == "Food Consumption") %>%
  transmute(region, commodity, year, food = value)

feed_total <- dt                                      %>% 
  filter(attribute_description == "Feed Consumption") %>%
  transmute(region, commodity, year, feed_total = value)

# Feed used to produce the three livestock (Z_ik), summed over livestock per input
# crop. NB: the decomposition's `input` uses USDA-style crop names -> recode.
feed_to_liv <- dt                                                                           %>%
  filter(attribute_description == "Total Feed Use of Input to produce livestock commodity") %>%
  mutate(commodity = input)                                                                 %>%
  group_by(region, commodity, year)                                                         %>%
  summarize(feed_to_liv = sum(value, na.rm = TRUE), .groups = "drop")

use <- food                                                          %>%
  full_join(feed_total,  by = c("region", "commodity", "year"))      %>%
  left_join(feed_to_liv, by = c("region", "commodity", "year"))      %>%
  mutate(across(c(food, feed_total, feed_to_liv), ~replace_na(., 0)),
         feed_other = feed_total - feed_to_liv,
         qty        = food + feed_other) 


# Expenditure (billion USD) and total per region-year
table(use$commodity, use$year)
table(price_base$commodity, price_base$marketing_year)

#NOTE: data available for prices and consumption quantities are only available 
#      for all commodities in 2025. Ag expenditure share thus are only calculated
#      using data from that year. Using data from 2026 might underestimate this
#      share, because the available data is not available for all commodities

expenditure_r  <- price_base                         %>%
  rename(year = marketing_year)                      %>%
  inner_join(use, by = c("year", "commodity"))       %>%
  filter(year == 2025)                               %>%
  mutate(expenditure = qty * price_conv * 1e6 / 1e9) %>%   # Million USD -> billion USD
  group_by(region, year)                             %>%
  summarize(total_exp = sum(expenditure, na.rm = TRUE), .groups = "drop")


# ---------------------------------------------------------------------------- #
# Denominator: real GDP (billion 2017 USD) projected by region and year
# ---------------------------------------------------------------------------- #

g   <- read.xlsx(input_path_gdp, sheet = 1, colNames = FALSE)
gdp <- data.frame(
  region_name = sub("\\s+[0-9]+/$", "", trimws(as.character(g[[1]]))),  # drop footnote markers
  gdp2025     = suppressWarnings(as.numeric(g[[2]])),
  g2025       = suppressWarnings(as.numeric(g[[6]])),
  g2026       = suppressWarnings(as.numeric(g[[7]])),
  g2027       = suppressWarnings(as.numeric(g[[8]])),
  g2028       = suppressWarnings(as.numeric(g[[9]])),
  g2029       = suppressWarnings(as.numeric(g[[10]])),
  gavg        = suppressWarnings(as.numeric(g[[13]])),   # 2026-35 average annual growth
  stringsAsFactors = FALSE
) %>% filter(!is.na(gdp2025))


# Project each GDP-file region's real GDP level for 2025..2034 (growth in percent)
years    <- 2025:2034
gdp_proj <- bind_rows(lapply(seq_len(nrow(gdp)), function(i) {
  r  <- gdp[i, ]
  gr <- c(r$g2026, r$g2027, r$g2028, r$g2029, rep(r$gavg, 5)) / 100   # 2025..2034
    data.frame(region_name = r$region_name, 
               year        = years,
               gdp         = r$gdp2025 * cumprod(c(1, 1 + gr))
               )
}))


# Crosswalk: 40 GDP-file regions map directly to our region codes
xwalk <- c(
  "Argentina"                     ="ARG", 
  "Australia"                     ="AUS", 
  "Bangladesh"                    ="BGD", 
  "Brazil"                        ="BRA",
  "Burma"                         ="BUR", 
  "Caribbean and Central America" ="CAC", 
  "Canada"                        ="CAN",
  "China"                         ="CHN", 
  "Other West African Community"  ="ECO", 
  "Egypt"                         ="EGY",
  "European Union 27"             ="EUR", 
  "Hong Kong"                     ="HKG", 
  "Indonesia"                     ="IDN", 
  "India"                         ="IND",
  "Iran"                          ="IRN", 
  "Iraq"                          ="IRQ", 
  "Japan"                         ="JPN", 
  "Cambodia"                      ="KHM", 
  "Korea"                         ="KOR",
  "Morocco"                       ="MAR", 
  "Mexico"                        ="MEX", 
  "Malaysia"                      ="MYS", 
  "Nigeria"                       ="NGA",
  "New Zealand"                   ="NZL", 
  "Other Europe"                  ="OEU", 
  "Other FSU-10"                  ="OFS",
  "Other Middle East"             ="OME", 
  "Other South America"           ="OSA",
  "Other Sub-Saharan Africa"      ="OSS", 
  "Pakistan"                      ="PAK", 
  "Philippines"                   ="PHL",
  "Russia"                        ="RUS", 
  "Saudi Arabia"                  ="SAU", 
  "Thailand"                      ="THA", 
  "Turkey"                        ="TUR",
  "Taiwan"                        ="TWN", 
  "Ukraine"                       ="UKR", 
  "United States"                 ="USA", 
  "Vietnam"                       ="VNM",
  "South Africa, Republic"        ="ZAF")

gdp_direct <- gdp_proj                  %>%
  filter(region_name %in% names(xwalk)) %>%
  mutate(region = xwalk[region_name])   %>%
  select(region, year, gdp)


# OAO = Other Asia & Oceania: residual of the Asia & Oceania aggregate
asia_leaves <- c("China","Hong Kong","Japan","Korea","Taiwan","Cambodia","Indonesia",
                 "Malaysia","Burma","Philippines","Thailand","Vietnam","Bangladesh",
                 "India","Pakistan","Australia","New Zealand")
gdp_oao <- gdp_proj                                             %>%
  filter(region_name %in% c("Asia and Oceania", asia_leaves))   %>%
  mutate(s = if_else(region_name == "Asia and Oceania", 1, -1)) %>%
  group_by(year)                                                %>% 
  summarize(gdp = sum(gdp * s), .groups = "drop")               %>%
  mutate(region = "OAO")


# ONA = Other North Africa: North Africa minus Egypt and Morocco
gdp_ona <- gdp_proj                                             %>%
  filter(region_name %in% c("North Africa", "Egypt", "Morocco"))%>%
  mutate(s = if_else(region_name == "North Africa", 1, -1))     %>%
  group_by(year)                                                %>% 
  summarize(gdp = sum(gdp * s), .groups = "drop") %>%
  mutate(region = "ONA")


# Real GDP from all countries
real_gdp <- bind_rows(gdp_direct,
                      gdp_oao %>% select(region, year, gdp),
                      gdp_ona %>% select(region, year, gdp))


# ---------------------------------------------------------------------------- #
# Ag expenditure share = food expenditure / real GDP (both billion 2017 USD)
# ---------------------------------------------------------------------------- #

# region name
region_name <- read_csv(input_path_mapping) %>%
  filter(group == "A")                      %>% 
  select(region_code, region_name)          %>%
  unique()                                  %>%
  rename(region = region_code)              %>%
  arrange(region)

ag_exp_share    <- expenditure_r                 %>%
  left_join(real_gdp, by = c("region", "year"))  %>%
  mutate(value = total_exp / gdp * 100)          


ag_exp_share_md <- ag_exp_share                  %>%
  group_by(region)                               %>%
  summarize(med_ag_share_r = median(value, na.rm = TRUE))  


years_bsat <- unique(dt$year)  

ag_exp_share_FN <- region_name                         %>%
  expand_grid(year = years_bsat)                       %>%
  left_join(ag_exp_share,    by = c("region", "year")) %>%
  left_join(ag_exp_share_md, by = c("region"))         %>%
  mutate(share = ifelse(!is.na(value), value, med_ag_share_r)) %>%
  select(region, region_name, year, share)             %>%
  rename(value = share)                                %>%
  mutate(
    attribute             = "Ag Expenditure Share",
    unit                  = "Percentage (%)",
    attribute_type        = "RY",
    attribute_description = "Ag Expenditure Share in BSAT products" 
  ) %>%
  filter(year ==2025)
#NOTE: if necessary the ag expenditure share for every year, it should be commented 
#       out the filter line above.

# ---------------------------------------------------------------------------- #
# Export results
# ---------------------------------------------------------------------------- #

write_csv(ag_exp_share_FN, ouput_path_ag_exp, na = "")              

          
    