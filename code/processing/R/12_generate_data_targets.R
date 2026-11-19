# ============================================================================ #
# 12_generate_data_targets.R
# Purpose:  Build data_targets.csv, the baseline levels the model is calibrated to,
#           from the long baseline table and the feed-use decomposition.
# Reads:    interim/baseline_projections_long.csv     (from 10_read_baseline_data.R)
#           interim/feed_use_decomposition.xlsx       (from 11_compute_feed_use_decomposition.R)
#           raw/mapping.csv
#           raw/baseline_units.csv                    (unit per commodity x attribute_description)
# Writes:   processed/data_targets.csv                (overwritten afterwards by 50_harmonize_targets.R)
# Depends:  dplyr, tidyr, readr, readxl (loaded by 00_load_packages.R)
# Notes:    lst_obsv_yr <- 2025 is the first year of the analysis period; keep it
#           equal to first_yr in 30_generate_data_shocks.R. Commodities are renamed
#           to model codes (Beef, SoyMeal, SoyOil, Soybean) and assigned to nests.
#           Soybean-market consistency check: when a region has SoyOil/SoyMeal
#           projections but no soybean market, SoyOil in BGD is reallocated to OAO
#           and SoyOil/SoyMeal in ECO to ONA (see the long note in the script). All
#           quantity attributes are rounded to whole units; yields and extraction
#           rates are not (13 re-derives them).
# ============================================================================ #
   
# ---------------------------------------------------------------------------- #
# Set file paths
# ---------------------------------------------------------------------------- #                                         
rm(list = ls())          

# base path
# NOTE: base_dir is the 'data' folder, relative to the project root (main.R sets the working directory).
# 'last observed' = the year of the last observed data in the baseline projections.
base_dir <- getOption("bsat.data_dir", file.path("..", "..", "data"))   # data root; set by main.R
lst_obsv_yr          <- 2025

# Input files
input_path_bsl_long <- file.path(base_dir, "interim", "baseline_projections_long.csv")
input_path_mapping  <- file.path(base_dir, "raw", "mapping.csv")
input_path_units    <- file.path(base_dir, "raw", "baseline_units.csv")
input_path_feed_use <- file.path(base_dir, "interim", "feed_use_decomposition.xlsx")

# Output files
output_path_data_targets         <- file.path(base_dir, "processed", "data_targets.csv")


# ---------------------------------------------------------------------------- #   
# Load long-format baseline projections
# ---------------------------------------------------------------------------- #
# Rename commodities
baseline_long <- read_csv(input_path_bsl_long) %>%           
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
    )
  )   

# Nest
baseline_long <- baseline_long %>%
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
    )
  )


# ---------------------------------------------------------------------------- #
# Distinguish area and crush
# ---------------------------------------------------------------------------- #
baseline_long <- baseline_long %>%
  mutate(
    crush     = if_else(commodity %in% c("SoyMeal", "SoyOil"),
                        area,
                        NA_real_),           # only SoyMeal & SoyOil get crush
    area      = if_else(commodity %in% c("Beef", "Pork", "Poultry", "SoyMeal", "SoyOil"),
                        NA_real_,             
                        area)                # keep original area otherwise
  )


# ---------------------------------------------------------------------------- #
# Distinguish yield and extraction rate
# ---------------------------------------------------------------------------- #
baseline_long <- baseline_long %>%
  mutate(
    extraction_rate = if_else(
                      commodity %in% c("SoyMeal","SoyOil"),
                      yield,
                      NA_real_            # only SoyMeal & SoyOil get extraction_rate
                    ),
    yield = if_else(
                      commodity %in% c("SoyMeal","SoyOil"),
                      NA_real_,           
                      yield               
                    )
  )


# ---------------------------------------------------------------------------- #
# Food and feed consumption
# ---------------------------------------------------------------------------- #
baseline_long <- baseline_long %>%
  mutate(
    food_cons = rowSums(select(., food_only, food_seed_ind, food_other), na.rm = TRUE),
    # no food consumption for Beef, Cotton, Pork, Poultry, Rice
    food_cons = if_else(commodity %in% c("Beef", "Cotton", "Pork", "Poultry", "Rice"), total_cons, food_cons),
    # USA-SoyOil-Food consumption
    food_cons = if_else(region == "UNITED STATES" & commodity == "SoyOil", total_cons, food_cons),
    
    feed_cons = rowSums(select(., feed_only, ind_feed_other, feed_seed_waste), na.rm = TRUE)
  ) %>%
  select(-food_only, -food_seed_ind, -food_other, -feed_only, -ind_feed_other, -feed_seed_waste)


# ---------------------------------------------------------------------------- #
# Beginning stocks
# ---------------------------------------------------------------------------- #
baseline_long <- baseline_long         %>% 
  arrange(region, commodity, year)     %>%         
  group_by(region, commodity)          %>%             
  mutate(begin_stock = lag(end_stock)) %>%     
  ungroup()


# ---------------------------------------------------------------------------- #
# Grouping
# ---------------------------------------------------------------------------- #
mapping <- read_csv(input_path_mapping)           %>%
  select(group, region_code, region, region_name) %>%
  unique()

baseline_long_m <- mapping     %>%
  left_join(baseline_long, by = c("region" = "region")) %>% # no World in the mapping
  select(-region)              %>%
  rename(region = region_code) %>%
  filter(group == "A")         %>% # only keep the A group
  select(-group)


# ---------------------------------------------------------------------------- #
# Generate data_targets.csv
# ---------------------------------------------------------------------------- #
data_targets <- baseline_long_m %>%
  select(-crush)                %>%                  # remove crush
  pivot_longer(
    cols       = -c(region, region_name, year, nest, commodity, commodity_name),  # keep these fixed
    names_to   = "attribute",                        # new column for old names
    values_to  = "value"                             # new column for their values
  )                             %>%
  filter(year >= lst_obsv_yr)


# attribute_description
data_targets <- data_targets %>%
  mutate(attribute_description = case_when(
    attribute == "area"             ~ "Area",
    attribute == "begin_stock"      ~ "Beginning Stocks",
    attribute == "crushing"         ~ "Crushing",
    attribute == "end_stock"        ~ "Ending Stocks",
    attribute == "exports"          ~ "Exports",
    attribute == "extraction_rate"  ~ "Extraction Rate",
    attribute == "feed_cons"        ~ "Feed Consumption",
    attribute == "food_cons"        ~ "Food Consumption",
    attribute == "imports"          ~ "Imports",
    attribute == "loss"             ~ "Loss",
    attribute == "production"       ~ "Production",
    attribute == "total_cons"       ~ "Total Consumption",
    attribute == "yield"            ~ "Yields",
    TRUE                            ~ attribute
  ))


# Filtering: e.g. only Soybeans Meal and Soybeans Oil get Extraction rate
#NOTE: the pivot_longer generates combinations region x commodity for some variables 
#      that do not exist in the baseline projection data. Even when they are reported 
#      as missing values, the code adjusts them as shown below.

data_targets <- data_targets %>%
  filter(
    !(!(commodity %in% c("SoyMeal", "SoyOil")) & attribute_description == "Extraction Rate"),
    !(!(commodity %in% c("Soybean"))           & attribute_description == "Crushing"),
    !(!(commodity %in% c("Cotton"))            & attribute_description == "Loss"),
    !(nest      == "Livestock"                 & (attribute_description == "Area"|attribute_description == "Yields")),
    !(nest      == "Secondary"                 & (attribute_description == "Area"|attribute_description == "Yields"))
  )

lapply(split(data_targets$commodity, data_targets$attribute), table)


# ---------------------------------------------------------------------------- #
# Additional variables
# ---------------------------------------------------------------------------- #

# nest_name
data_targets <- data_targets %>%
  mutate(
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
    )
  )


# input and attribute_type
data_targets <- data_targets %>%
  mutate(
    input = "",
    attribute_type = "RYNC"
  )


# baseline units
baseline_units <- read_csv((input_path_units)) %>%
  select(-commodity_name)

data_targets <- data_targets %>%
  left_join(baseline_units, by = c("commodity", "attribute_description")) 


# loading feed use decomposition data
feed_use_dec <- read_excel(input_path_feed_use) 


# formatting and appending feed use data
data_targets <- data_targets                %>%
  mutate(attribute = attribute_description) %>%
  bind_rows(., feed_use_dec)                %>%
  select(region, year, nest, commodity, input, attribute, value, Z_k, value_share, unit, 
         attribute_type, attribute_description, region_name, nest_name, commodity_name) %>%
  arrange(region, year, commodity, attribute)


# ------------------------------------------------------------------------------------------- #
# Evaluating consistency between the Soybean market and Soybean Meal and Soybean Oil markets
# ------------------------------------------------------------------------------------------- #

# NOTE: the consistency between Soybeans, and  Soybean Meal, and Soybean Oil markets
#       consists of examining whether a soybean meal and/or soybean oil region 
#       producer produces, imports or stores soybeans. From a theoretical standpoint
#       it does not make sense that a region produces soybeans meal and/or soybeans 
#       oil if it does not produce, import or stores soybeans; their main input. 

data_soy_chk = data_targets %>%
  filter(
    ( commodity %in% c("Soybean", "SoyMeal", "SoyOil")),
    ( attribute %in% c("Production", "Imports", "Beginning Stocks")),
   !((commodity %in% c("SoyMeal", "SoyOil")) & attribute %in% c("Imports", "Beginning Stocks"))
  )

table(data_soy_chk$commodity, data_soy_chk$attribute)


# Identification of atypical cases
data_soy_chk <- data_soy_chk                 %>%
  filter(value > 0 & !is.na(value))          %>%
  select(region, year, commodity, attribute) %>%
  mutate(
    x_ = 1,                            
    attribute = case_when(
      attribute == "Production"       ~ "Q_",
      attribute == "Imports"          ~ "M_",
      attribute == "Beginning Stocks" ~ "BS_",
      TRUE                            ~ attribute
    )
  )


data_soy_chk_wide <- data_soy_chk %>%
  pivot_wider(
    names_from  = attribute,
    values_from = x_
    )   %>%
  pivot_wider(
    names_from  = commodity,
    values_from = c(M_, Q_, BS_),
    )   %>%
  select(-M__SoyMeal, -M__SoyOil, -BS__SoyMeal, -BS__SoyOil)  %>%
  mutate(
    Q__SoyMeal  = replace_na(Q__SoyMeal, 0),
    Q__SoyOil   = replace_na(Q__SoyOil,  0),
    Q__Soybean  = replace_na(Q__Soybean, 0),
    M__Soybean  = replace_na(M__Soybean, 0),
    BS__Soybean = replace_na(BS__Soybean, 0)
    )


# Generation of indicators for determining the consistency between markets
  data_soy_chk_wide <- data_soy_chk_wide %>%
    mutate(
      id_SEC = (Q__SoyMeal + Q__SoyOil)                / (Q__SoyMeal + Q__SoyOil),
      id_SOY = (Q__Soybean + M__Soybean + BS__Soybean) / (Q__Soybean + M__Soybean + BS__Soybean)
    ) %>%
    mutate(
      id_SEC = if_else(is.na(id_SEC), 0, id_SEC),
      id_SOY = if_else(is.na(id_SOY), 0, id_SOY)
    ) %>%
    mutate(
      x = id_SOY - id_SEC
    )

  #IMPORTANT: if _SEC = 1 and id_SOY = 1 => x = 0  exists soybeans and soybeans related markets 
  #           if _SEC = 0 and id_SOY = 1 => x = 1  exists soybeans market but it does not 
  #                                                of soybeans related markets 
  #           if _SEC = 1 and id_SOY = 0 => x = -1 exists an inconsistency between both 
  #                                                soybeans market and soybeans related markets 
  
  data_soy_chk_wide <- data_soy_chk_wide %>% 
    filter(x < 0)

    if (nrow(data_soy_chk_wide) == 0) {
      message("soybean markets is consistent with soy related markets") 
      data_targets <- data_targets %>%
        select(-Z_k, -value_share)
    
  } else {
    
    data_soy_chk_long <- data_soy_chk_wide        %>%
      select(region, year, Q__SoyOil, Q__SoyMeal) %>%
      pivot_longer(
        cols         = starts_with("Q__"),
        names_to     = "commodity",
        names_prefix = "Q__",
        values_to = "value"
      ) %>%
      filter(value==1)  

    table(data_soy_chk_long$region, data_soy_chk_long$commodity, data_soy_chk_long$year)    
    
    # IMPORTANT: The previous tables show that the following markets exhibit a consistency
    #            issue between the soybean market and the corresponding SoyOil and SoyMeal
    #             markets:
    #
    #            (a) SoyOil in BGD (Bangladesh) for all years.
    #            (b) SoyOil and SoyMeal in ECO (West African Countries) for all years.
    #
    #            In these cases, the USDA provides projections for the SoyOil and/or
    #            SoyMeal markets but does not report projections for the corresponding
    #            soybean market. We interpret this as an indication that soybean activity
    #            exists in these regions but is relatively small. As a result, the USDA
    #            may include these soybean markets within larger aggregate regions
    #            (e.g., soybean in Bangladesh being included in Other Asia).
    #
    #            To ensure data consistency, we reallocate the corresponding projections
    #            as follows, previously revising that these activities exist in those regions:
    #
    #            - All SoyOil data from Bangladesh are aggregated into Other Asia SoyOil.
    #            - All SoyOil and SoyMeal data from West African Countries are aggregated
    #              into North Africa.
    #                
    #            We follow the same aggregation approach when adjusting the demand for
    #            livestock products that use these commodities as feed inputs. However,
    #            this requires that the corresponding livestock activity exists in the
    #            region receiving the aggregated demand. If the livestock activity does
    #            not exist in that region, we assume that its demand for the relevant
    #            commodity (i.e., SoyOil and/or SoyMeal) is equal to zero.
    #
    #            In practice, this means that we adjust the value shares used to
    #            decompose the feed demand of each livestock activity, assigning a
    #            value share of zero whenever the corresponding livestock activity is
    #            not present in the region.

    
  #) Adjustment at commodity x region level
    # Extraction Rate is intentionally excluded from this reallocation and
    # removed with the original rows below; the downstream Julia code recomputes it.
    data_adj_DA_COM <- data_targets %>%
      filter(
        (  commodity %in% c("SoyOil", "SoyMeal")),
        (  region    %in% c("BGD", "OAO", "ECO", "ONA")),
        (!(attribute %in% c("Extraction Rate")))
      ) %>%
      mutate(
        region      = if_else(region == "BGD" & commodity =="SoyOil" , "OAO", region),
        region      = if_else(region == "ECO" & commodity =="SoyOil" , "ONA", region),
        region      = if_else(region == "ECO" & commodity =="SoyMeal", "ONA", region),
        
        region_name = if_else(region_name == "Bangladesh"                                    & commodity =="SoyOil", 
                              "Other Asia & Oceania", region_name),
        region_name = if_else(region_name == "West African Community=Ecowas (minus Nigeria)" & commodity =="SoyOil", 
                              "Other North Africa", 
                              region_name),
        region_name = if_else(region_name == "West African Community=Ecowas (minus Nigeria)" & commodity =="SoyMeal", 
                              "Other North Africa", 
                              region_name),        
      ) %>% 
      group_by(
        region, year, nest, commodity, input, attribute, unit,
        attribute_type, attribute_description, region_name,
        nest_name, commodity_name
      ) %>%
      summarise(
        value = sum(value, na.rm = TRUE),                   
        .groups = "drop"
      )
    table(data_adj_DA_COM$commodity, data_adj_DA_COM$region)

    
#) Adjustment at commodity x region x input
    data_adj_DA_LIV <- data_targets %>%
      filter(
        ( attribute  %in% c("Total_feed_use_input_to_commodity")),        
        (  commodity %in% c("Beef", "Pork", "Poultry")),
        (  input     %in% c("SoyOil", "SoyMeal")),
        (  region    %in% c("BGD", "OAO", "ECO", "ONA"))
      )
    
    data_adj_DA_LIV_pos <- data_adj_DA_LIV %>%
      filter(value > 0 & !is.na(value) )
    table(data_adj_DA_LIV_pos$commodity, data_adj_DA_LIV_pos$region)

    #NOTE: this table shows that all livestock activities exists in Other Asia (OAO)
    #      and in North Other Africa (ONA), with the exception of pork. Accordingly. 
    #      we adjust the data as explained above
    
    
    data_adj_DA_LIV <- data_adj_DA_LIV %>%
      mutate(
        region      = if_else(region == "BGD" & input =="SoyOil"                      , "OAO", region),
        region      = if_else(region == "ECO" & input =="SoyOil"  & commodity !="Pork", "ONA", region),
        region      = if_else(region == "ECO" & input =="SoyMeal" & commodity !="Pork", "ONA", region),
        
        region_name = if_else(region_name == "Bangladesh"                                    & input =="SoyOil", 
                              "Other Asia & Oceania", region_name),
        region_name = if_else(region_name == "West African Community=Ecowas (minus Nigeria)" & input =="SoyOil"
                              & commodity !="Pork", "Other North Africa", region_name),
        region_name = if_else(region_name == "West African Community=Ecowas (minus Nigeria)" & input =="SoyMeal" 
                              & commodity !="Pork", "Other North Africa", region_name),       
        value       = if_else(region == "ECO" & input =="SoyOil"   & commodity =="Pork", 0, value),
        value       = if_else(region == "ECO" & input =="SoyMeal"  & commodity =="Pork", 0, value)
      ) %>% 
      group_by(
        region, year, nest, commodity, input, attribute, unit,
        attribute_type, attribute_description, region_name,
        nest_name, commodity_name
      ) %>%
      summarise(
        value = sum(value, na.rm = TRUE),
        .groups = "drop"
      )

    
    # Adjusted targets_data when necessary
    data_targets <- data_targets  %>%
      select(-Z_k, -value_share)  %>% 
      filter(
        !(  commodity   %in%  c("SoyOil", "SoyMeal")        &
            region      %in%  c("BGD", "OAO", "ECO", "ONA") 
        )) %>%
      filter(
        !(
            attribute   %in%  c("Total_feed_use_input_to_commodity") &
            commodity   %in%  c("Beef", "Pork", "Poultry")           &
            input       %in%  c("SoyOil", "SoyMeal")                 &
            region      %in%  c("BGD", "OAO", "ECO", "ONA")
        )) %>%  
      bind_rows(., data_adj_DA_COM) %>% 
      bind_rows(., data_adj_DA_LIV)       
  }  
        
  # NOTE: The baseline projections contain small numerical discrepancies
  #       between supply and demand in some markets. We calculate supply as
  #       the sum of beginning stocks, production, and imports minus losses,
  #       and demand as the sum of total consumption, exports, and ending
  #       stocks.
  #
  #       For example, in 2025 the supply of Rice in Hong Kong is reported
  #       as 312.0 thousand metric tons (entirely driven by imports), while
  #       demand is reported as 311.895056784094 thousand metric tons
  #       (entirely driven by total consumption). This results in a
  #       discrepancy of approximately 0.105 thousand metric tons.
  #
  #       To address this issue, we round the values of all attributes.
  #       This approach ensures that markets such as Rice in Hong Kong clear
  #       naturally without requiring further adjustments. However, rounding
  #       can occasionally introduce new discrepancies. For example, consider
  #       a market with production equal to 12.6 thousand metric tons, total
  #       consumption equal to 6.2 thousand metric tons, and exports equal to
  #       6.4 thousand metric tons. After rounding, production becomes 13
  #       thousand metric tons, while total consumption and exports both
  #       become 6 thousand metric tons. As a result, supply equals 13,
  #       whereas demand equals 12.
  #
  #       In these cases, we handle the remaining discrepancy in the Julia
  #       model by adding it to or subtracting it from the supply component
  #       with the largest value. We avoid applying this adjustment to demand
  #       attributes because doing so could affect total consumption. As a
  #       result, total consumption might no longer equal the sum of food and
  #       feed consumption.
  #
  #       We also avoid assigning the discrepancy to ending stocks. This
  #       approach can be problematic in cases such as Rice in Hong Kong,
  #       where ending stocks are originally equal to zero. In such cases,
  #       the adjustment would create a stock level that is positive but very
  #       small, leading Julia to calibrate the model using an artificial
  #       value that could introduce numerical noise.
  #
  #       Below, we round the value of all attributes except by the value of
  #       yields and extraction rate. We also examine the occasional discrepancy
  #       that this approach generates in the market of every product and within
  #       total consumption. The result is essential to the adjustment we apply to  
  #       the data in the model in Julia.

  data_targets <- data_targets %>% 
    mutate( 
      value = if_else(attribute %in% c("Area", "Beginning Stocks", "Crushing", 
                                       "Ending Stocks", "Exports", "Feed Consumption", 
                                       "Food Consumption", "Imports", "Loss", 
                                       "Production", "Total Consumption", 
                                       "Total_feed_use_input_to_commodity"),      
                      round(value), value))


  
  # Examining the remaining discrepancy
  
  #a) Overall market region x commodity
  data_check <- data_targets %>%
    filter(
      attribute %in% c("Beginning Stocks", "Ending Stocks", "Exports", "Imports", 
                       "Loss", "Production", "Total Consumption")) %>%
    select("region", "year", "commodity", "attribute", "value")    %>%
    rename(v_ = value)                                             %>%
    mutate(
      attribute = case_when(
        attribute == "Beginning Stocks"   ~ "BS",
        attribute == "Ending Stocks"      ~ "ES",
        attribute == "Exports"            ~ "X",
        attribute == "Imports"            ~ "M",
        attribute == "Loss"               ~ "L",
        attribute == "Production"         ~ "Q",
        attribute == "Total Consumption" ~ "TC",
      )) %>%
    pivot_wider(
      names_from  = attribute,
      values_from = v_
    )   %>%
    mutate(across(everything(), ~ replace_na(., 0)))  
  
  data_check$Supply <- (data_check$BS + data_check$Q + data_check$M) - data_check$L
  data_check$Demand <- (data_check$TC + data_check$X + data_check$ES) 
  data_check$Dif    <- abs(data_check$Supply - data_check$Demand)
  
  table(data_check$Dif)
  #NOTE: this table shows that most discrepancy is of 1 thousand metric ton 
  #      and in very few cases of 2 thousand metric tons

  
  #b) Consumption market region x commodity
  data_check_cons <- data_targets %>%
    filter(
      attribute %in% c("Feed Consumption", "Food Consumption", "Total Consumption", "Crushing")) %>%
    select("region", "year", "commodity", "attribute", "value")    %>%
    rename(v_ = value)                                             %>%
    mutate(
      attribute = case_when(
        attribute == "Feed Consumption"   ~ "Feed",
        attribute == "Food Consumption"   ~ "Food",
        attribute == "Crushing"           ~ "Crush",
        attribute == "Total Consumption"  ~ "TC",
      )) %>%
    pivot_wider(
      names_from  = attribute,
      values_from = v_
    )   %>%
    mutate(across(everything(), ~ replace_na(., 0)))  

  data_check_cons$Dif    <- abs(data_check_cons$TC - (data_check_cons$Feed + data_check_cons$Food + data_check_cons$Crush))
   
  table(data_check_cons$Dif)
  #NOTE: this table shows that most discrepancy is of 1 thousand metric ton 
  
  
# ---------------------------------------------------------------------------- #
# Save data_targets.csv
# ---------------------------------------------------------------------------- #

write_csv(data_targets, output_path_data_targets, na = "")

                
                                                                 
           
   
