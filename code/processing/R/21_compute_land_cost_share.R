# ============================================================================ #
# 21_compute_land_cost_share.R
# Purpose:  Compute the land cost share of value added (phi_f) for every region
#           and crop from U.S. per-acre variable costs, relative yields and the
#           USDA international TFP land cost shares.
# Reads:    raw/AgTFPInternational2023.xlsx             (sheet "Cost Shares", rows 3-182, cols 3 and 33: ISO3, "2021-2030")
#           raw/variable_costs_2025/*to 2035*.xlsx      (five USDA cost-of-production workbooks)
#           raw/mapping.csv
#           interim/baseline_projections_long.csv       (from 10: area and yield by region and crop)
# Writes:   interim/variable_costs_us_2025.csv          (extracted U.S. per-acre variable costs, long)
#           interim/region_commodity_land_cost_shares.csv
# Depends:  openxlsx, dplyr, readr (loaded by 00_load_packages.R)
# Notes:    Vintage constants: vc_pattern <- "to 2035" selects the cost workbooks in
#           raw/variable_costs_2025/; the land-share column is renamed from its
#           header "2021-2030". The EUR land share is hard-coded at 0.113. Cost
#           workbooks are parsed by row label: "Table ... U.S. <crop>", an "Item"
#           header row with the crop years, "Variable costs of production" and the
#           following "Per acre" row. Land rents solve
#           w * sum_k s_rk / (H_rk + w) = land share with uniroot on [0, 1000];
#           shares are winsorized at the 5th and 95th percentiles within each
#           year. Years >= 2025 are exported.
# ============================================================================ #

# ---------------------------------------------------------------------------- #
# Set file paths
# ---------------------------------------------------------------------------- #    

rm(list = ls())

# base path
# NOTE: base_dir is the 'data' folder, relative to the project root (main.R sets the working directory).
base_dir <- getOption("bsat.data_dir", file.path("..", "..", "data"))   # data root; set by main.R

# Input files
input_path_land_share <- file.path(base_dir, "raw"    , "AgTFPInternational2023.xlsx")
input_path_mapping    <- file.path(base_dir, "raw"    , "mapping.csv")
input_path_bsl_long   <- file.path(base_dir, "interim", "baseline_projections_long.csv")
input_path_vc_dir     <- file.path(base_dir, "raw"    , "variable_costs_2025")
   
# Latest-vintage USDA cost-of-production files to read   
vc_pattern            <- "to 2035"

# Output files
output_path_vc_us            <- file.path(base_dir, "interim", "variable_costs_us_2025.csv")
output_path_land_cost_share  <- file.path(base_dir, "interim", "region_commodity_land_cost_shares.csv")


# ---------------------------------------------------------------------------- #
# Prepare cost-related data
# ---------------------------------------------------------------------------- #

# Region-level land cost shares
# ---------------------------------------------------------------------------- #
land_share_r <- read.xlsx(input_path_land_share, 
                          sheet = "Cost Shares",
                          rows  = 3:182, 
                          cols  = c(3, 33)) %>%
  rename(land_share_r = `2021-2030`)        %>%
  mutate(ISO3 = ifelse(`ISO3` == "MMR", "BUR", `ISO3`))


mapping <- read_csv(input_path_mapping) 

# Land Cost share at region level
land_share_r <- mapping                                           %>%
  left_join(land_share_r, by = c("country_code" = "ISO3"))        %>%
  select(region_code, land_share_r)                               %>%
  group_by(region_code)                                           %>%
  summarize(land_share_r = median(land_share_r, na.rm = TRUE))    %>%
  # EUR's land share comes from AgTFPInternational2023.xlsx
  mutate(land_share_r    = ifelse(region_code == "EUR", 0.113, land_share_r))


# ---------------------------------------------------------------------------- #
# Area and yield data
# ---------------------------------------------------------------------------- #
baseline_long <- read_csv(input_path_bsl_long)

cost_related  <- baseline_long                              %>%
  select(region, commodity, year, yield, area, production)  %>%
  filter(year >= 2024 & 
           !(commodity %in% c("Beef and veal", "Pork", "Poultry", "Soybean meal", "Soybean oil")))

# Yield for the United States
yield_us <- cost_related            %>%
  filter(region == "UNITED STATES") %>%
  select(year, commodity, yield)    %>%
  distinct()                        %>%
  rename(yield_us = yield)

# Area and yield data for the Rest of the World
cost_related_r <- mapping                             %>%
  select(group, region_code, region, region_name)     %>%
  distinct()                                          %>%
  left_join(cost_related, by = c("region"))           %>% 
  select(-group)                                      %>%
  select(year, region_code, region_name, commodity, yield, area) %>%
  filter(!is.na(commodity))


# Variable costs for the United States
# ---------------------------------------------------------------------------- #
# Read the U.S. per-acre variable cost of each crop directly from the USDA
# cost-of-production projection files. In every file, each crop section has a
# row "Variable costs of production (dollars):" whose next row (" Per acre")
# holds the per-year value; the crop name comes from the "Table ... U.S. <crop>"
# header and the years from the "Item" header row.

# Map a "Table ... U.S. <crop> ..." label to the baseline commodity name
normalize_crop <- function(x) {
  x <- tolower(x)
  if (grepl("oats", x))    return(NA_character_)   # oats not modeled
  if (grepl("corn", x))    return("Corn")
  if (grepl("sorghum", x)) return("Sorghum")
  if (grepl("barley", x))  return("Barley")
  if (grepl("rice", x))    return("Rice")
  if (grepl("soybean", x)) return("Soybeans")
  if (grepl("cotton", x))  return("Cotton")
  if (grepl("wheat", x))   return("Wheat")
  NA_character_
}


# Extract the per-acre variable cost (long format) from one cost file
extract_vc_us <- function(f) {
  res <- list()
  for (s in getSheetNames(f)) {
    d          <- read.xlsx(f, sheet = s, colNames = FALSE)
    lab        <- trimws(as.character(d[[1]]))
    vc_rows    <- which(grepl("Variable costs of production", lab))
    item_rows  <- which(grepl("^Item", lab))
    table_rows <- which(grepl("^Table", lab))
    for (r in vc_rows) {
      crop <- normalize_crop(lab[max(table_rows[table_rows < r])])
      if (is.na(crop)) next
      ir   <- max(item_rows[item_rows < r])           # nearest year header
      yrs  <- as.character(unlist(d[ir,  -1]))
      # locate the "Per acre" value row after the header by label (robust to a
      # blank row between them, which openxlsx may or may not drop)
      pa <- which(lab == "Per acre" & seq_along(lab) > r)
      if (length(pa) == 0) next
      vals <- suppressWarnings(as.numeric(unlist(d[pa[1], -1])))
      keep <- !is.na(yrs) & !is.na(vals)
      res[[length(res) + 1]] <- data.frame(commodity = crop,
                                           year = yrs[keep], vc_us = vals[keep])
    }
  }
  bind_rows(res)
}   


vc_files <- list.files(input_path_vc_dir, pattern = vc_pattern, full.names = TRUE)
vc_us    <- bind_rows(lapply(vc_files, extract_vc_us)) %>%
  arrange(commodity, year)



# Save the assembled U.S. variable costs, then convert the crop year to integer
write_csv(vc_us, output_path_vc_us)

vc_us <- vc_us %>%
  mutate(year = as.integer(sub("/.*$", "", year)))


# ---------------------------------------------------------------------------- #
# merge all cost-related data
# ---------------------------------------------------------------------------- #
cost_related_merged <- cost_related_r                 %>%
  left_join(yield_us,     by = c("year","commodity")) %>%
  left_join(land_share_r, by = "region_code")         %>% 
  left_join(vc_us,        by = c("year","commodity"))

# Drop missing values (incl. years with no U.S. variable-cost data)
cost_related_merged <- cost_related_merged %>%
  filter(!is.na(land_share_r), !is.na(vc_us), if_any(c(area, yield), ~. != 0))


# ---------------------------------------------------------------------------- #
# Computation of land cost shares at the region-commodity level 
# ---------------------------------------------------------------------------- #

# Units: 
# area: 1000 hectares
# yield: metric tons per hectare (except cotton whose unit is kilograms per hectare)
# variable costs: dollar


cost <- cost_related_merged


# Land area shares
# ---------------------------------------------------------------------------- #
cost <- cost                  %>%
  group_by(year, region_code) %>%
  mutate(total_area = sum(area),
         s_rk = area/total_area)


# First, we compute region-commodity land cost shares for the US 
# ---------------------------------------------------------------------------- #
cost_US <- cost[cost$region_code == "USA", ]

# Compute land rents and beta_rk for the US
cost_US <- cost_US  %>%
  group_by(year)    %>%
  mutate(w_usl    = land_share_r/sum(s_rk/vc_us),
         beta_usk = w_usl/vc_us)


# Second, we compute region-commodity land cost shares for all other regions 
# ---------------------------------------------------------------------------- #
# Merge the US land shares to the cost data frame
cost <- cost %>%
  left_join(cost_US[c("year","commodity", "beta_usk", "w_usl")], by = c("year","commodity"))


# Compute the non-land cost: H_rk
cost <- cost %>%
  mutate(H_rk = (yield/yield_us)*(1-beta_usk)*vc_us)


# Solve land rents
# Note that we do not know variable costs in other regions
# we need to solve a non-linear equation for land rents first

# Define f(w, land_share_r, s_rk, H_rk) to set up the root-finding problem
f <- function(w, land_share_r, s_rk, H_rk) {
  return(w*sum(s_rk/(H_rk+w)) - land_share_r)
}

# Test the function
a <- f(41,cost$land_share_r[1], cost$s_rk, cost$H_rk) 
print(a)


# Define a function to find the solution for land rents
find_rent      <- function(df) {
  land_share_r <- df$land_share_r[1]
  s_rk         <- df$s_rk
  H_rk         <- df$H_rk
  
  g <- function(w) {
    f(w, land_share_r, s_rk, H_rk)
  }
  rent <- uniroot(g, interval = c(0,1000))
  return(rent$root)
}


# Solve for land rents: w_rl
cost <- cost                  %>%
  group_by(year, region_code) %>%
  mutate(w_rl = find_rent(pick(everything())))


# Now we have both land rents and non-land cost for all other regions
# we can directly compute the commodity-level land cost shares
# ---------------------------------------------------------------------------- #

# compute the region-commodity level land cost shares: beta_rk
cost <- cost %>%
  group_by(year, region_code)  %>%
  mutate(vc_rk   = H_rk + w_rl,
         beta_rk = w_rl/vc_rk) %>%
  ungroup()


# Extract the region-commodity land cost shares
# ---------------------------------------------------------------------------- #
land_cost_shares <- select(cost, year, region_code, region_name, commodity, vc_rk, beta_rk)
land_cost_shares <- land_cost_shares %>%
  arrange(year, region_code, commodity)


# Winsorize the results to avoid extreme values
# ---------------------------------------------------------------------------- #
# Clamp beta_rk to its 5th and 95th percentiles within each year. Identical to
# DescTools::Winsorize (0.99.60), which is not used: its conda-forge Windows
# build fails to load, and the loader error dialog hangs a headless Rscript.

land_cost_shares <- land_cost_shares %>%
  group_by(year)                     %>%
  mutate(beta_rk_winsor = {
    q <- quantile(beta_rk, probs = c(0.05, 0.95), na.rm = TRUE)
    pmin(pmax(beta_rk, q[1L]), q[2L])
  })

summary(land_cost_shares$beta_rk)
summary(land_cost_shares$beta_rk_winsor)


# ---------------------------------------------------------------------------- #
# Final adjustments 
# ---------------------------------------------------------------------------- #
land_cost_shares <- land_cost_shares                                %>% 
  select(year, region_code, region_name, commodity, beta_rk_winsor) %>%
  rename(region = region_code)                                      %>%
  mutate(
    commodity_name = commodity,
    commodity_name = case_when(
      commodity_name == "Soybeans" ~ "Soybean",
      TRUE                         ~ commodity_name
    ),  
    commodity = case_when(
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
    attribute             = "phi_f",
    attribute_type        = "RYNC" ,
    attribute_description = "Distribution Parameter of land within value added of crops"
  )                              %>%
  rename(value = beta_rk_winsor) %>%
  filter(year>=2025)


# ---------------------------------------------------------------------------- #
# Save the results
# ---------------------------------------------------------------------------- #
write_csv(land_cost_shares, output_path_land_cost_share)   


     