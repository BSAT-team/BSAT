# ============================================================================ #
# 23_compute_NTM_ave.R
# Purpose:  Estimate a model of non-tariff-measure ad valorem equivalents (AVE) on
#           tariffs, GDP per capita and agricultural imports with region x product
#           fixed effects, impute missing AVEs, and aggregate them into GDP-weighted
#           region-commodity import NTMs; export NTMs are a zero scaffold.
# Reads:    raw/trade_barriers/ave_hs_importer.csv             (World Bank NTM AVEs: importer, hs2code, ave1C, ave2C)
#           raw/trade_barriers/BACI_HS92_Y2014_V202401b.csv    (CEPII bilateral flows 2014: t, i, j, k, v, q; large, not in the repo)
#           raw/trade_barriers/country_codes_V202401b.csv      (BACI numeric code -> country_iso3)
#           raw/trade_barriers/ag_hs_products.csv              (agricultural HS product list, column Product)
#           raw/trade_barriers/ag_tariff_USA_2014.xls           (sheet "Applied_MFN", column E from row 6: HS6 codes)
#           raw/trade_barriers/tariff_ave_2014_WITS.csv         (WITS 2014 tariff AVEs; large, not in the repo)
#           raw/trade_barriers/country_code_WITS.xlsx           (Reporter -> ISO3)
#           raw/trade_barriers/country_region_WB.xlsx           (sheet "List of economies", rows 1-219, cols 2-3: Code, Region)
#           raw/current_GDPpc_2014_WB.csv                       (World Bank, column "2014 [YR2014]")
#           raw/current_GDP_2014_WB.csv                         (World Bank, column "2014 [YR2014]")
#           raw/current_GDPpc_IMF.xls                           (IMF WEO, Taiwan only)
#           raw/current_GDP_IMF.xls                             (IMF WEO, Taiwan only)
#           raw/mapping.csv
# Writes:   interim/model_estimates.RData         (rxp_fe and the four beta coefficients)
#           interim/NTM_regression_results.csv    (coefficients, standard errors and fit statistics)
#           interim/NTM_regression_table.tex      (the same results as a LaTeX table for the paper)
#           interim/NTM_ave_imputed.RData        (NTM_ave_imputed: country x commodity actual and imputed AVE)
#           interim/NTM_IMP_ave_region.csv
#           interim/NTM_EXP_ave_region.csv
# Depends:  dplyr, tidyr, readr, readxl, openxlsx, lfe (loaded by 00_load_packages.R)
# Notes:    Sourced by main.R only when both large raw files are present; otherwise
#           the two interim CSVs are reused (see main.R and
#           scripts/fetch_large_raw_data.sh). Regression: ave ~ AVE_Tariff +
#           AVE_Tariff_ag + log_GDPpc + log_total_imp_ag | region_geo:product_id
#           (felm). Negative imputations are set to 0; gaps for Barley, Sorghum,
#           Soybeans and Wheat take the country's Corn/Rice/Cotton average; Iraq
#           takes its geographic-region average. EU members plus GBR are pooled as
#           EUN; Myanmar MMR -> BUR; Taiwan is BACI code 490. World Bank regions are
#           merged into Euro-MENA and Asia-Pacific for the fixed effects. Reference
#           year of all inputs is 2014. Diagnostics: 25_compare_actual_imputed_NTM.R.
# ============================================================================ #

# ---------------------------------------------------------------------------- #        
# Set file paths
# ---------------------------------------------------------------------------- #

rm(list = ls())

# base path
# NOTE: base_dir is the 'data' folder, relative to the project root (main.R sets the working directory).
base_dir <- getOption("bsat.data_dir", file.path("..", "..", "data"))   # data root; set by main.R

# Input files
input_path_NTM         <- file.path(base_dir, "raw", "trade_barriers/ave_hs_importer.csv")
input_path_trade       <- file.path(base_dir, "raw", "trade_barriers/BACI_HS92_Y2014_V202401b.csv")
input_path_BACI_code   <- file.path(base_dir, "raw", "trade_barriers/country_codes_V202401b.csv")
input_path_ag_goods    <- file.path(base_dir, "raw", "trade_barriers/ag_hs_products.csv")

input_path_GDPpc       <- file.path(base_dir, "raw","current_GDPpc_2014_WB.csv")
input_path_GDPpc_twn   <- file.path(base_dir, "raw","current_GDPpc_IMF.xls")
input_path_GDP         <- file.path(base_dir, "raw","current_GDP_2014_WB.csv")
input_path_GDP_twn     <- file.path(base_dir, "raw","current_GDP_IMF.xls")

input_path_hs6         <- file.path(base_dir, "raw", "trade_barriers/ag_tariff_USA_2014.xls")
input_path_tariff      <- file.path(base_dir, "raw", "trade_barriers/tariff_ave_2014_WITS.csv")
input_path_WITS_code   <- file.path(base_dir, "raw", "trade_barriers/country_code_WITS.xlsx")
input_path_region      <- file.path(base_dir, "raw", "trade_barriers/country_region_WB.xlsx")

input_path_mapping     <- file.path(base_dir, "raw","mapping.csv")

# Output files
output_path_estimates  <- file.path(base_dir, "interim", "model_estimates.RData")
output_path_reg_csv    <- file.path(base_dir, "interim", "NTM_regression_results.csv")
output_path_reg_tex    <- file.path(base_dir, "interim", "NTM_regression_table.tex")
output_path_imputed    <- file.path(base_dir, "interim", "NTM_ave_imputed.RData")
output_path_NTM_imp    <- file.path(base_dir, "interim", "NTM_IMP_ave_region.csv")
output_path_NTM_exp    <- file.path(base_dir, "interim", "NTM_EXP_ave_region.csv")


# ---------------------------------------------------------------------------- #
#   Load main data
# ---------------------------------------------------------------------------- #

# AVE of NTMs
# Source: https://datacatalog.worldbank.org/search/dataset/0040437
ave_hs_importer <- read.csv(input_path_NTM) %>%
  mutate(ave = rowSums(cbind(ave1C, ave2C), na.rm = TRUE)) %>%
  select(-ave1C, -ave2C) %>%
  rename(HS_code = hs2code) %>%
  # Add leading zeros to HS_code
  mutate(  
    HS_code = as.character(HS_code), 
    HS_code = if_else(
      nchar(HS_code) == 5, 
      paste0("0", HS_code),
      HS_code 
    )
  )


# Bilateral trade flow data (2014)
import_BACI <- read.csv(input_path_trade)

import_bilateral <- import_BACI %>%
  select(-q) %>%
  rename(
    year = t, 
    exporter = i, 
    importer = j,
    HS_code = k, 
    import = v
  )


# ---------------------------------------------------------------------------- #
#   2014 trade data
# ---------------------------------------------------------------------------- #

# Aggregate import (importer-hs6 level)
# ---------------------------------------------------------------------------- #

import_agg <- import_bilateral %>%
  group_by(importer, HS_code) %>%
  summarise(import = sum(import, na.rm = TRUE), .groups = "drop")

# Country code (BACI)
country_code_BACI <- read.csv(input_path_BACI_code) %>%
  # Taiwan (Asia, not elsewhere specified - 490)
  mutate(country_iso3 = if_else(country_code == "490", "TWN", country_iso3),
         country_iso3 = if_else(country_code == "104", "BUR", country_iso3)) %>% 
  select(country_code, country_iso3) %>%
  rename(importer = country_code) 

# EU contries - including UK
EU_countries <- c("AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST", "FIN", 
                  "FRA", "DEU", "GRC", "HUN", "IRL", "ITA", "LVA", "LTU", "LUX", 
                  "MLT", "NLD", "POL", "PRT", "ROU", "SVK", "SVN", "ESP", "SWE",
                  "GBR")


# Add ISO 3 code to import_agg
import_agg <- import_agg %>%
  left_join(country_code_BACI, by = c("importer" = "importer")) %>%
  select(-importer) %>%
  rename(importer = country_iso3) %>%
  # Add leading zeros to HS_code
  mutate( 
    HS_code = as.character(HS_code), 
    HS_code = if_else(nchar(HS_code) == 5, paste0("0", HS_code), HS_code)
  ) %>%
  mutate(
    importer = if_else(importer %in% EU_countries, "EUN", importer)
  ) %>%
  group_by(importer, HS_code) %>%
  summarise(import = sum(import, na.rm = TRUE), .groups = "drop")


# Mark ag hs products - trade flow data
# ---------------------------------------------------------------------------- #

# Agricultural products hscode
ag_hs_products <- read.csv(input_path_ag_goods) %>%
  rename(HS_code = Product) %>%
  select(HS_code) %>%
  distinct() %>%
  filter(HS_code != "WTO_HS_Aggri") %>%
  mutate(Type = "AG")


# Total agricultural imports for each country
import_total_ag <- import_agg %>%
  left_join(ag_hs_products, by = "HS_code") %>%
  filter(!is.na(Type)) %>%
  group_by(importer) %>%
  mutate(total_imp_ag = sum(import)) %>%
  ungroup() %>%
  select(importer, total_imp_ag) %>%
  distinct() %>%
  arrange(importer) %>%
  # Aggregate EU countries
  mutate(
    importer = if_else(importer %in% EU_countries, "EUN", importer)
  ) %>%
  group_by(importer) %>%
  summarise(total_imp_ag = sum(total_imp_ag), .groups = "drop") %>%
  mutate(
    importer = if_else(importer == "MMR", "BUR", importer) # Myanmar (Burma)
  )


# ---------------------------------------------------------------------------- #
#   2014 GDP and GDP per capita (current USD)
# ---------------------------------------------------------------------------- #

# Load GDP per capita
# ---------------------------------------------------------------------------- #
GDPpc <- read.csv(input_path_GDPpc) %>%
  rename(
    importer = Country.Code, 
    GDPpc = `X2014..YR2014.`
  ) %>%
  select(importer, GDPpc) %>%
  filter(!(GDPpc %in% c("..", NA))) %>%
  mutate(GDPpc = as.numeric(GDPpc),
         importer = if_else(importer == "EUU", "EUN", importer),
         importer = if_else(importer == "MMR", "BUR", importer))

# Add Taiwan, data from IMF
GDPpc_TWN <- read_excel(input_path_GDPpc_twn) %>%
  rename(
    importer = `GDP per capita, current prices\n (U.S. dollars per capita)`, 
    GDPpc = `2014`
  ) %>%
  select(importer, GDPpc) %>%
  filter(importer == "Taiwan Province of China") %>%
  mutate(importer = "TWN",
         GDPpc = as.numeric(GDPpc))

# Append
GDPpc <- rbind(GDPpc, GDPpc_TWN)


# Load GDP
# ---------------------------------------------------------------------------- #
GDP <- read.csv(input_path_GDP) %>%
  rename(
    importer = Country.Code, 
    GDP = `X2014..YR2014.`
  ) %>%
  select(importer, GDP) %>%
  filter(!(GDP %in% c("..", NA))) %>%
  mutate(GDP = as.numeric(GDP),
         importer = if_else(importer == "EUU", "EUN", importer),
         importer = if_else(importer == "MMR", "BUR", importer))

# Add Taiwan, data from IMF
GDP_TWN <- read_excel(input_path_GDP_twn) %>%
  rename(
    importer = `GDP, current prices (Billions of U.S. dollars)`, 
    GDP = `2014`
  ) %>%
  select(importer, GDP) %>%
  filter(importer == "Taiwan Province of China") %>%
  mutate(importer = "TWN",
         GDP = as.numeric(GDP)*1e9) # Convert to USD

# Append
GDP <- rbind(GDP, GDP_TWN)

rm(GDPpc_TWN, GDP_TWN)


# ---------------------------------------------------------------------------- #
#   Tariff data
# ---------------------------------------------------------------------------- #

# Load 2014 tariff data (WITS)
ave_tariff <- read.csv(input_path_tariff)

# Load ISO 3 code for WITS data
country_code_WITS <- read.xlsx(input_path_WITS_code) %>%
  mutate(
    ISO3 = if_else(ISO3 == "MMR", "BUR", ISO3)
  )

# MFN tariff data: fewer missing values
ave_tariff_MFN <- ave_tariff %>% 
  filter(DutyType == "MFN") %>%
  select(Reporter, Product, Simple.Average) %>% 
  rename(AVE_Tariff = Simple.Average) %>%
  # Add leading zero to HS_code
  mutate(  
    Product = as.character(Product), 
    Product = if_else(
      nchar(Product) == 5 | nchar(Product) == 3, 
      paste0("0", Product),
      Product 
    )
  )

# Add ISO 3 code
ave_tariff_MFN <- ave_tariff_MFN %>%
  left_join(country_code_WITS, by = c("Reporter")) %>%
  select(-Reporter, -country) %>%
  arrange(ISO3, Product) 

# Ag average tariff
ave_tariff_MFN <- ave_tariff_MFN %>%
  left_join(ag_hs_products, by = c("Product" = "HS_code")) %>%
  group_by(ISO3) %>%
  mutate(
    AVE_Tariff_ag = mean(AVE_Tariff[Type == "AG"], na.rm = TRUE)
  ) %>%
  select(-Type)

# ---------------------------------------------------------------------------- #
#  Load geographical region (region fixed effects)
#  Combine some region - there won't be no obs in Middle East & North Africa and South Asia
# ---------------------------------------------------------------------------- #
region_WB <- read.xlsx(input_path_region, sheet = "List of economies", rows=1:219, cols=2:3) %>%
  rename(
    importer = Code, 
    region_geo = Region
  ) %>%
  arrange(region_geo, importer) %>%
  mutate(
    region_geo = if_else(region_geo %in% c("Europe & Central Asia", "Middle East & North Africa"), "Euro-MENA", region_geo), 
    region_geo = if_else(region_geo %in% c("East Asia & Pacific", "South Asia"), "Asia-Pacific", region_geo),
    importer = if_else(importer %in% EU_countries, "EUN", importer)
  ) %>%
  distinct() %>%
  mutate(
    importer = if_else(importer == "MMR", "BUR", importer) # Myanmar (Burma)
  )


# ---------------------------------------------------------------------------- #
#   Match all data
# ---------------------------------------------------------------------------- #

NTM_ave <- ave_hs_importer %>%
  left_join(import_agg, by = c("HS_code" = "HS_code", "importer" = "importer")) %>%
  left_join(import_total_ag, by = c("importer" = "importer")) %>%
  left_join(GDPpc, by = c("importer" = "importer")) %>%
  left_join(GDP, by = c("importer" = "importer")) %>%
  left_join(region_WB, by = c("importer" = "importer")) %>%
  left_join(ave_tariff_MFN, by = c("importer" = "ISO3", "HS_code" = "Product")) # MFN tariff data

NTM_ave <- NTM_ave %>%
  left_join(ag_hs_products, by = c("HS_code")) %>%
  mutate(
    Type = if_else(is.na(Type), "Non-AG", Type)
  )


# Data for regression
NTM_ave_reg <- NTM_ave %>%
  mutate(
    GDPpc = as.numeric(GDPpc),
    GDP = as.numeric(GDP),
    import = as.numeric(import)
  ) %>%
  # Take logs
  mutate(                            
    log_GDPpc = log(GDPpc),
    log_import = log(import),
    log_GDP = log(GDP),
    log_total_imp_ag = log(total_imp_ag)
  )


# ---------------------------------------------------------------------------- #
#   Map hs code to baseline commodities
# ---------------------------------------------------------------------------- #

# Baseline commodity-hscode mapping
# The WTO schedule is not distributed with the repository (WTO terms). The derived
# commodity-to-HS6 mapping is shipped in data/interim/commodity_hs6_mapping.csv and used
# whenever the schedule is absent; with the schedule present the mapping is rebuilt from it.
input_path_hs6_map <- file.path(base_dir, "interim", "commodity_hs6_mapping.csv")
if (file.exists(input_path_hs6)) {
  commodity_hscode <- read_excel(input_path_hs6, sheet = "Applied_MFN", 
                                                     range = cell_cols("E"), skip = 5, col_names  = "HS_code") %>% 
    filter(nchar(HS_code) == 6) %>%
    select(HS_code) %>%
    distinct() %>%
    mutate(
      HS_code_4 = substr(HS_code, 1, 4)
    ) %>%
    arrange(HS_code_4, HS_code)%>%
    mutate(
      commodity = case_when(
        HS_code %in% c("0201", "0202", "020610", "020621", "020622", "020629", "021020") ~ "Beef and veal",
        HS_code %in% c("0207") ~ "Poultry",
        HS_code %in% c("0203", "020630", "020641", "020649", "020910", "021011", "021012", "021019") ~ "Pork",
        HS_code %in% c("1006") ~ "Rice",
        HS_code %in% c("1001") ~ "Wheat",
        HS_code %in% c("1005") ~ "Corn",
        HS_code %in% c("1003") ~ "Barley",
        HS_code %in% c("1007") ~ "Sorghum",
        HS_code %in% c("5201", "5202", "5203") ~ "Cotton",
        HS_code %in% c("1201") ~ "Soybeans",
        HS_code %in% c("2304") ~ "Soybean meal",
        HS_code %in% c("1507") ~ "Soybean oil",
        HS_code_4 %in% c("0201", "0202", "020610", "020621", "020622", "020629", "021020") ~ "Beef and veal",
        HS_code_4 %in% c("0207") ~ "Poultry",
        HS_code_4 %in% c("0203", "020630", "020641", "020649", "020910", "021011", "021012", "021019") ~ "Pork",
        HS_code_4 %in% c("1006") ~ "Rice",
        HS_code_4 %in% c("1001") ~ "Wheat",
        HS_code_4 %in% c("1005") ~ "Corn",
        HS_code_4 %in% c("1003") ~ "Barley",
        HS_code_4 %in% c("1007") ~ "Sorghum",
        HS_code_4 %in% c("5201", "5202", "5203") ~ "Cotton",
        HS_code_4 %in% c("1201") ~ "Soybeans",
        HS_code_4 %in% c("2304") ~ "Soybean meal",
        HS_code_4 %in% c("1507") ~ "Soybean oil",
        TRUE ~ "Other"
      )
    ) %>%
    filter(commodity != "Other") %>%
    select(-HS_code_4) %>%
    arrange(commodity, HS_code)
  write_csv(commodity_hscode, input_path_hs6_map)
} else if (file.exists(input_path_hs6_map)) {
  commodity_hscode <- read_csv(input_path_hs6_map, col_types = cols(.default = col_character()))
  cat("23_compute_NTM_ave: WTO schedule absent; using the shipped mapping", input_path_hs6_map, "\n")
} else {
  stop("Neither ", input_path_hs6, " nor ", input_path_hs6_map, " was found.")
}


NTM_ave_reg_ag <- NTM_ave_reg %>%
  filter(Type == "AG") %>%
  left_join(commodity_hscode, by = c("HS_code")) %>%
  rename(product_id = HS_code) %>%
  mutate(product_id = if_else(!is.na(commodity), commodity, product_id)) %>%
  group_by(importer, product_id) %>%
  summarise(
    ave = mean(ave, na.rm = TRUE),
    AVE_Tariff = mean(AVE_Tariff, na.rm = TRUE),
    region_geo = first(region_geo),
    AVE_Tariff_ag = first(AVE_Tariff_ag),
    log_GDPpc = first(log_GDPpc),
    log_total_imp_ag = first(log_total_imp_ag),
    .groups = "drop"
  )

# Used for fixed effects
NTM_ave_reg_ag$region_geo <- as.factor(NTM_ave_reg_ag$region_geo)
NTM_ave_reg_ag$product_id <- as.factor(NTM_ave_reg_ag$product_id)


# ---------------------------------------------------------------------------- #
#   Regression
# ---------------------------------------------------------------------------- #

model <- felm(
  ave ~ AVE_Tariff + AVE_Tariff_ag + log_GDPpc + log_total_imp_ag | region_geo:product_id, 
  data = NTM_ave_reg_ag
)

summary(model)

# Get fixed effects
fixed_effects <- getfe(model)

rxp_fe <- fixed_effects %>% 
  filter(fe == "region_geo:product_id") %>%
  select(idx, effect) %>%
  rename(
    region_product = idx, 
    rxp_fe=effect
  )

# Get coefficients
coefficients      <- coef(model)

beta_tariff       <- coefficients[1]
beta_tariff_ag    <- coefficients[2]
beta_GDPpc        <- coefficients[3]
beta_total_imp_ag <- coefficients[4]


## Save estimates
save(rxp_fe, beta_tariff, beta_tariff_ag, beta_GDPpc,
     beta_total_imp_ag, file = output_path_estimates)


## Save regression results (reported in the appendix of the paper)
model_sum <- summary(model)
reg_coef  <- model_sum$coefficients
reg_terms <- c(AVE_Tariff       = "Tariff",
               AVE_Tariff_ag    = "Average agricultural tariff",
               log_GDPpc        = "log GDP per capita",
               log_total_imp_ag = "log agricultural imports")

reg_results <- data.frame(
  term      = rownames(reg_coef),
  estimate  = reg_coef[, 1],
  std_error = reg_coef[, 2],
  t_value   = reg_coef[, 3],
  p_value   = reg_coef[, 4],
  row.names = NULL
)
reg_stats <- data.frame(
  term      = c("n_obs", "r_squared", "adj_r_squared", "within_r_squared", "n_fixed_effects"),
  estimate  = c(model_sum$N, model_sum$r.squared, model_sum$adj.r.squared,
                model_sum$P.r.squared, nrow(rxp_fe)),
  std_error = NA, t_value = NA, p_value = NA
)
write_csv(bind_rows(reg_results, reg_stats), output_path_reg_csv)

# LaTeX table: estimates with significance stars, standard errors in parentheses
stars <- function(p) ifelse(p < 0.01, "^{***}", ifelse(p < 0.05, "^{**}", ifelse(p < 0.1, "^{*}", "")))
coef_lines <- unlist(lapply(seq_len(nrow(reg_results)), function(k) c(
  sprintf("%s & $%.4f%s$ \\\\", reg_terms[[reg_results$term[k]]],
          reg_results$estimate[k], stars(reg_results$p_value[k])),
  sprintf(" & $(%.4f)$ \\\\", reg_results$std_error[k])
)))
reg_tex <- c(
  "\\begin{tabular}{lc}",
  "\\hline\\hline",
  " & AVE of NTMs \\\\",
  "\\hline",
  coef_lines,
  "\\hline",
  sprintf("Observations & %s \\\\", format(model_sum$N, big.mark = ",")),
  sprintf("$R^2$ & %.3f \\\\", model_sum$r.squared),
  sprintf("Within $R^2$ & %.3f \\\\", model_sum$P.r.squared),
  sprintf("Region--product fixed effects & %s \\\\", format(nrow(rxp_fe), big.mark = ",")),
  "\\hline\\hline",
  "\\end{tabular}"
)
writeLines(reg_tex, output_path_reg_tex)

# ---------------------------------------------------------------------------- #
#   Generate identifiers
# ---------------------------------------------------------------------------- #

# Load baseline mapping data
mapping <- read_csv(input_path_mapping) %>%
  filter(!country %in% c("Former Yemen North Sanaa", "Former Yemen South Aden")) %>%
  mutate(country_code = if_else(region == "EUROPEAN UNION", "EUN", country_code)) %>%
  mutate(country = if_else(region == "EUROPEAN UNION", "EUROPEAN UNION", country)) %>%
  distinct()


# Country and commodity code
country_codes <- unique(mapping$country_code)

commodities <- c(
  "Barley", "Beef and veal", "Corn", "Cotton", "Pork", "Poultry", "Rice", 
  "Sorghum", "Soybean meal", "Soybean oil", "Soybeans", "Wheat"
)

# country-commodity identifier
country_commodity <- expand.grid(country_code = country_codes, commodity = commodities) %>%
  arrange(country_code, commodity)

# region-country-commodity identifier
NTM_ave_country <- mapping %>%
  left_join(country_commodity, by = "country_code")

# Map AVE data to country level
NTM_ave_country <- NTM_ave_country %>%
  # match region fes 
  left_join(region_WB, by = c("country_code" = "importer")) %>%                       
  select(group, region_code, region, country_code, country, everything()) %>%
  arrange(group, region_code, country_code, commodity) %>%
  mutate(region_product = paste(region_geo, commodity, sep = "."))


# ---------------------------------------------------------------------------- #
#   Impute missing values using estimates from the OLS model
# ---------------------------------------------------------------------------- #

load(output_path_estimates)


ave_tariff_MFN_commodity <- ave_tariff_MFN %>%
  left_join(commodity_hscode, by = c("Product" = "HS_code")) %>% 
  filter(!is.na(commodity)) %>%
  group_by(ISO3, commodity) %>%
  mutate(
    AVE_Tariff = mean(AVE_Tariff, na.rm = TRUE)
  ) %>%
  select(ISO3, commodity, AVE_Tariff, AVE_Tariff_ag) %>%
  distinct()

NTM_ave_commodity <- ave_hs_importer %>%
  left_join(commodity_hscode, by = c("HS_code" = "HS_code")) %>%
  filter(!is.na(commodity)) %>%
  group_by(importer, commodity) %>%
  mutate(
    ave = mean(ave, na.rm = TRUE)
  ) %>%
  select(importer, commodity, ave) %>%
  distinct()


# Prepare data
# ---------------------------------------------------------------------------- #
NTM_ave_impute <- NTM_ave_country %>%
  left_join(NTM_ave_commodity, by = c("country_code" = "importer", "commodity")) %>%
  left_join(GDPpc, by = c("country_code" = "importer")) %>%
  left_join(GDP, by = c("country_code" = "importer")) %>%
  left_join(import_total_ag, by = c("country_code" = "importer")) %>%
  left_join(ave_tariff_MFN_commodity, by = c("country_code" = "ISO3", "commodity")) %>%
  mutate(
    log_GDPpc = log(GDPpc),
    log_GDP = log(GDP), 
    log_total_imp_ag = log(total_imp_ag)
  ) %>%
  select(-GDPpc, -GDP, -total_imp_ag)


# Match estimates: coefficients and fixed effects
NTM_ave_impute <- NTM_ave_impute %>%
  left_join(rxp_fe, by = c("region_product")) %>%
  mutate(
    beta_tariff = beta_tariff,
    beta_GDPpc = beta_GDPpc,
    beta_total_imp_ag = beta_total_imp_ag
  )


# Imputation
# ---------------------------------------------------------------------------- #
NTM_ave_imputed <- NTM_ave_impute %>%
  mutate(
    ave_hat = beta_tariff * AVE_Tariff + beta_tariff_ag * AVE_Tariff_ag + beta_GDPpc * log_GDPpc + beta_total_imp_ag * log_total_imp_ag + rxp_fe
  ) %>%
  select(group, region_code, region, region_geo, country_code, country, commodity, 
         ave, ave_hat, AVE_Tariff, beta_tariff, log_GDPpc, beta_GDPpc, log_total_imp_ag, 
         beta_total_imp_ag, rxp_fe)

save(NTM_ave_imputed, file = output_path_imputed)


# ---------------------------------------------------------------------------- #
#   Calculate aggregated AVE at region-commodity level
# ---------------------------------------------------------------------------- #

load(output_path_imputed)

# country-commodity level
# ---------------------------------------------------------------------------- #
NTM_ave_cc <- NTM_ave_imputed %>%
  select(group, region_code, region, country_code, country, region_geo, commodity, ave, ave_hat) %>%
  left_join(GDP, by = c("country_code" = "importer")) %>%  # GDP will be used for weighting
  mutate(
    ave_hat = if_else(ave_hat < 0, 0, ave_hat) # replace negative imputed values with zero
  ) %>%
  mutate(
    ave = if_else(is.na(ave), ave_hat, ave) # replace missing actual values with imputed values
  ) %>%
  select(-ave_hat) %>%
  group_by(group, country_code) %>%
  mutate(
    ave_crop = mean(ave[commodity %in% c("Corn", "Rice", "Cotton")], na.rm = TRUE) # simple average for crops
  ) %>%
  ungroup() %>%
  mutate(
    ave_cc = if_else(is.na(ave) & commodity %in% c("Barley", "Sorghum", "Soybeans", "Wheat"), ave_crop, ave) # replace missing values with simple average of crops
  ) %>%
  select(-ave, -ave_crop) 

# Add Iraq
NTM_ave_cc <- NTM_ave_cc %>%
  group_by(region_geo, commodity) %>%
  mutate(
    ave_geo = mean(ave_cc, na.rm = TRUE) # regional average
  ) %>%
  ungroup() %>%
  mutate(
    ave_cc = if_else(country_code == "IRQ", ave_geo, ave_cc)
  ) %>%
  select(-ave_geo, -region_geo)

# region-commodity level
# re-aggregate region
# ---------------------------------------------------------------------------- #
NTM_ave_cc <- NTM_ave_cc %>%
  mutate(region_code = if_else(group != "A", "ROW", region_code),
         region = if_else(group != "A", "Rest of World", region)) %>%
  select(-group)


NTM_ave_rc <- NTM_ave_cc %>%
  group_by(region_code, commodity) %>%
  mutate(
    GDP = if_else(is.na(GDP), 0, GDP), 
    ave_rc = weighted.mean(ave_cc, w = GDP, na.rm = TRUE) # weighted average
  ) %>%
  ungroup() %>%
  select(-ave_cc, -GDP, -country_code, -country) %>%
  distinct() %>%
  select(-region) %>%
  rename(region = region_code) %>%
  arrange(region, commodity)


# ---------------------------------------------------------------------------- #
# Final format adjustments  
# ---------------------------------------------------------------------------- #

# region name
region_name <- read_csv(input_path_mapping) %>%
  filter(group == "A")                      %>% 
  select(region_code, region_name)          %>%
  unique()                                  %>%
  rename(region = region_code)              %>%
  arrange(region)

# Final data
NTM_ave_rc <- NTM_ave_rc %>%
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
    attribute             = "NTM for importing a product",
    attribute_type        = "RNC" ,
    attribute_description = "Non Tariff Measure for importing a product",
    unit                  = "decimal form"
    , 
    value = ave_rc /100
  )                %>%
  select(-ave_rc)  %>%
  left_join(region_name, by = "region") 
  
   
# ---------------------------------------------------------------------------- #
# Exporting: import NTMs to CSV
# ---------------------------------------------------------------------------- #

write_csv(NTM_ave_rc, file = output_path_NTM_imp)





# ---------------------------------------------------------------------------- #
# Export NTMs
# ---------------------------------------------------------------------------- #

# NOTE: data on export NTMs is not available for any region and commodity. Since 
#       export NTMs may affect global markets, they are included in the model 
#       and are assumed equal to zero for all combinations of region x commodity 
#       in the benchmark scenario.


commodities <- unique(NTM_ave_rc$commodity_name)
exp_NTM_FN  <- mapping                      %>%
  select(region_code, region_name)          %>%
  unique()                                  %>%
  expand_grid(commodity = commodities)      %>%
  mutate(value = 0  )                     
  

exp_NTM_FN <- exp_NTM_FN                    %>%    
  rename(region = region_code)              %>%
  mutate(
    commodity_name = commodity,
    commodity      = case_when(
      commodity == "Beef and veal" ~ "Beef",
      commodity == "Soy Meal"      ~ "SoyMeal",
      commodity == "Soy Oil"       ~ "SoyOil",
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
    attribute             = "NTM for exporting a product",
    attribute_type        = "RNC" ,
    attribute_description = "Non Tax Measure for exporting a product",
    unit                  = "decimal form",
  )                              


# ---------------------------------------------------------------------------- #
# Exporting: export NTMs to CSV
# ---------------------------------------------------------------------------- #

write_csv(exp_NTM_FN, file = output_path_NTM_exp)




