# ============================================================================ #
# 40_generate_data_params_init.R
# Purpose:  Generate data_params_init.csv, the initial values of the seven
#           commodity-level substitution and transformation elasticities.
# Reads:    none
# Writes:   processed/data_params_init.csv
# Depends:  dplyr, readr (loaded by 00_load_packages.R)
# Notes:    Values are hard-coded: sigma_d 3.8 (12 commodities), sigma_f 1.1
#           (7 crops), sigma_c 5 (SoyMeal, SoyOil), sigma_l 0.25, sigma_z 0.5 and
#           sigma_w 3.8 (livestock), omega_s 5 (12 commodities); 42 rows with
#           attribute_type "C".
# ============================================================================ #

# ---------------------------------------------------------------------------- #
# Set file paths
# ---------------------------------------------------------------------------- #

rm(list = ls())    

# base path
# NOTE: base_dir is the 'data' folder, relative to the project root (main.R sets the working directory).
base_dir <- getOption("bsat.data_dir", file.path("..", "..", "data"))   # data root; set by main.R

# Output files
output_path_data_params    <- file.path(base_dir, "processed", "data_params_init.csv")



# ---------------------------------------------------------------------------- #        
# Initial parameters
# ---------------------------------------------------------------------------- #

# sigma_d
  sigma_d = data.frame( 
              commodity = c("Corn", "Wheat", "Sorghum", "Soybean", "SoyMeal",
                       "SoyOil", "Barley", "Cotton", "Rice", "Beef",
                       "Poultry", "Pork")
                      )%>%
              mutate(
                attribute             = "sigma_d",
                value                 = 3.8, 
                attribute_description = "elasticity of substitution (in demand) between a domestic and an imported product"
                )

# sigma_f
  sigma_f = data.frame( 
              commodity = c("Corn", "Wheat", "Sorghum", "Soybean", "Barley", 
                            "Cotton", "Rice")
                      )%>%
              mutate(
                attribute             = "sigma_f",
                value                 = 1.1, 
                attribute_description = "elasticity of substitution (in factors) between land and no land for producing every product"
                )

# sigma_c
  sigma_c = data.frame( 
              commodity = c("SoyOil", "SoyMeal")
                      )%>%
              mutate(
                attribute             = "sigma_c",
                value                 = 5, 
                attribute_description = "elasticity of substitution (in intermediate) between domestic and imported intermediate inputs (crushed soybeans)"
                )
  
# sigma_l
  sigma_l = data.frame( 
              commodity = c("Beef", "Poultry", "Pork")
                      )%>%
              mutate(
                attribute             = "sigma_l",
                value                 = 0.25, 
                attribute_description = "elasticity of substitution (in LIVESTOCK production) between feed and non-feed"
                )

# sigma_z
  sigma_z = data.frame( 
              commodity = c("Beef", "Poultry", "Pork")
                      )%>%
              mutate(
                attribute             = "sigma_z",
                value                 = 0.5, 
                attribute_description = "elasticity of substitution (in LIVESTOCK production) across commodities used as feed"
                )

# sigma_w
  sigma_w = data.frame( 
              commodity = c("Beef", "Poultry", "Pork")
                      )%>%
              mutate(
                attribute             = "sigma_w",
                value                 = 3.8, 
                attribute_description = "elasticity of substitution (in LIVESTOCK production) between domestic and imported commodities used as feed"
                )

# omega_s
  omega_s = data.frame( 
              commodity = c("Corn", "Wheat", "Sorghum", "Soybean", "SoyMeal",
                       "SoyOil", "Barley", "Cotton", "Rice", "Beef",
                       "Poultry", "Pork")
                      )%>%
              mutate(
                attribute             = "omega_s",
                value                 = 5, 
                attribute_description = "elasticity of transformation (in supply) between domestic and export market"
                )

# ---------------------------------------------------------------------------- #
# All raw initial parameters information  
# ---------------------------------------------------------------------------- #

params <- bind_rows(sigma_d, sigma_f, sigma_c, sigma_l, sigma_z, sigma_w, omega_s) %>%
          mutate(
            region         = "",
            year           = "",
            input          = "",
            attribute_type = "C",
            region_name    = "",
            unit           = ""
          )%>%
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
          ))%>%
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
            ))%>%
          mutate(
            commodity_name = commodity,
            commodity_name = case_when(
            commodity_name == "SoyMeal"  ~ "Soy Meal",
            commodity_name == "SoyOil"   ~ "Soy Oil", 
            commodity_name == "Beef"     ~ "Beef and veal",
            TRUE                              ~ commodity_name
            ))%>%
          select(region, year, nest, commodity, input, attribute, value, unit, 
                  attribute_type, attribute_description, region_name, nest_name, commodity_name)
  

# ---------------------------------------------------------------------------- #
# Save params_data.csv
# ---------------------------------------------------------------------------- #

write_csv(params, output_path_data_params, na = "")

  

