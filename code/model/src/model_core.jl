#  --------------------------------------------------------------------------------------------------
#                       BSAT model core, v2.27 (July 29, 2026)
#          Manuel I. Jimenez, Diego Cardoso, Hao Xiong and Russell Hillberry, Purdue University
#  --------------------------------------------------------------------------------------------------
#  This file is the year loop of the original "BSAT_Model_v.2.27 (Final USER CODE).jl", copied
#  verbatim (original lines 88 to 3825). It contains the data preparation, calibration, model
#  specification, solve, and per-year result extraction. It is evaluated by BSATRunner.run() with
#  the working directory set to a scratch folder that holds Input/, and with the global `periods`
#  defined. Do not edit: every change to the model must be reviewed by the model authors, and the
#  regression test (test/runtests.jl) compares the output with the archived reference run.
#  --------------------------------------------------------------------------------------------------

for i in periods
#---------------  
    print(i)       
    println(" ")  


#  --------------------------------------------------------------------------------------------------
# PART B: LOADING OF ALL INFORMATION
#  --------------------------------------------------------------------------------------------------

    # All required data is organized in four dataframes. 
    #              (1) Parameters
    #              (2) Exogenous data
    #              (3) USDA targets
    #              (4) Shocks data
    #
    #           - All dataframes follow the harmonized format previously defined in the data standardization.
    #         
    #           - NOT all variables are specified at the same level. Depending on the variable, each dataframe specifies the level 
    #             at which it is used in the model. In case a variable does not have a specified dimension, this indicates that a 
    #             variable takes the given value regardless of the dimension (i.e. it is a scalar). 
    
    local  info_parameters, info_exogenous, info_targets_0, info_targets, info_Shocks_0, info_Shocks


    #) Loading Parameters
        info_parameters = CSV.read("Input/data_params_init.csv", DataFrame)

    #) Loading Exogenous Data 
        info_exogenous  = CSV.read("Input/data_exogenous.csv"  , DataFrame)

    #) Loading USDA Projections
        info_targets_0  = CSV.read("Input/data_targets.csv"    , DataFrame)
        info_targets    = info_targets_0[info_targets_0.year .== i, :]

    #) Loading Shocks 
        info_Shocks_0   = CSV.read("Input/data_shocks.csv"     , DataFrame)
        info_Shocks     = info_Shocks_0[info_Shocks_0.year   .== i, :]




#  --------------------------------------------------------------------------------------------------
#
#                                    3. MODEL SET UP
#
#  --------------------------------------------------------------------------------------------------
           

#  --------------------------------------------------------------------------------------------------
# PART A: IDENTIFIERS 
#  --------------------------------------------------------------------------------------------------

    local  year, region, commodity, pri_goods, sec_goods, soy_inp_goods, liv_goods, inp_liv, factors, nest, nsC, nsL, nsI, nsT, nsB, nsP, 
           nsS, nsR

    #) Overall identifiers
        year          = sort(unique(info_targets.year))
        region        = sort(unique(info_targets.region))
        commodity     = sort(unique(info_targets.commodity))
        pri_goods     = sort!(["Barley","Corn", "Cotton", "Rice","Sorghum", "Soybean", "Wheat"])        
        sec_goods     = sort!(["SoyOil","SoyMeal"])
        soy_inp_goods = sort!(["Soybean"]) 
        liv_goods     = sort!(["Beef","Pork","Poultry"])       
        inp_liv       = sort!(["Barley","Corn", "Sorghum", "SoyOil", "SoyMeal", "Soybean", "Wheat"])   
        factors       = sort!(["Land","No_Land"])
        nest          = sort(unique(info_targets.nest))

    #) Commodities within every nest 
        nsC        = sort!(["Corn","Sorghum"])
        nsL        = sort!(["Beef","Pork","Poultry"])
        nsI        = sort!(["SoyMeal", "SoyOil"])
        nsT        = sort!(["Cotton"])
        nsB        = sort!(["Wheat"])     
        nsP        = sort!(["Barley"])
        nsS        = sort!(["Soybean"])
        nsR        = sort!(["Rice"])  

    #NOTE: Throughout this code, some labels (i.e., commented text) use indices to refer to previously defined elements. The concordances are listed below:
    #      r: region
    #      k: commodity
    #      g: commodity (i.e., this is an alias for commodity k)
    #      n: nest
    #      z: soy_inp_goods
    #      x: liv_goods   


#  --------------------------------------------------------------------------------------------------
# PART B: PARAMETERS 
#  --------------------------------------------------------------------------------------------------

    local  sigma_t_0, sigma_t, sigma_u_0, sigma_u, sigma_n_0, sigma_n, sigma_a_0, sigma_a, sigma_d_0, sigma_d, sigma_i_0, sigma_i, 
           sigma_f_0, sigma_f, sigma_c_0, sigma_c, sigma_l_0, sigma_l, sigma_z_0, sigma_z, sigma_w_0, sigma_w, omega_q_0, omega_q, 
           omega_s_0, omega_s, omega_c_0, omega_c         

# 1) Elasticities of substitution

    #) sigma_t  elasticity of substitution (in demand) between Ag y No Ag
        sigma_t_0 = sort!(info_exogenous[info_exogenous.attribute .== "sigma_t", :])  
        sigma_t   = sigma_t_0[:,:value][1] 

    #) sigma_u  elasticity of substitution (in demand) across commodity nests
        sigma_u_0 = sort!(info_exogenous[info_exogenous.attribute .== "sigma_u", :])  
        sigma_u   = sigma_u_0[:,:value][1]

    #) sigma_n(n)  elasticity of substitution (in demand) within every nest n 
        sigma_n_0 = sort!(info_exogenous[info_exogenous.attribute .== "sigma_n", :])  
        sigma_n   = Dict(sigma_n_0.nest .=> sigma_n_0.value) 

    #) sigma_a(k)  elasticity of substitution (in demand) between food and feed uses of commodity k
        sigma_a_0 = sort!(info_exogenous[info_exogenous.attribute .== "sigma_a", :])      
        sigma_a   = Dict(sigma_a_0.commodity .=> sigma_a_0.value) 

    #) sigma_d(k)  elasticity of substitution (in demand) between domestic and imported commodity k   
        sigma_d_0 = sort!(info_parameters[info_parameters.attribute .== "sigma_d", :]) 
        sigma_d   = Dict(sigma_d_0.commodity .=> sigma_d_0.value)

    #) sigma_i(k)  elasticity of substitution (in CROPS production) between value added and intermediate inputs in the production of commodity k
        sigma_i_0 = sort!(info_exogenous[info_exogenous.attribute .== "sigma_i", :]) 
        sigma_i   = Dict(sigma_i_0.commodity .=> sigma_i_0.value)

    #) sigma_f(k)  elasticity of substitution (in PRIMARY CROPS production) between land and the non-land inputs bundle in the production of commodity k
        sigma_f_0 = sort!(info_parameters[info_parameters.attribute .== "sigma_f", :]) 
        sigma_f   = Dict(sigma_f_0.commodity .=> sigma_f_0.value)

    #) sigma_c(k) elasticity of substitution (in SECONDARY CROPS production) between domestic and imported intermediate inputs (i.e., soybeans) in the production of commodity k
        sigma_c_0 = sort!(info_parameters[info_parameters.attribute .== "sigma_c", :])
        sigma_c   = Dict(sigma_c_0.commodity .=> sigma_c_0.value)

    #) sigma_l(k)  elasticity of substitution (in LIVESTOCK production) between feed and non-feed for producing commodity k
        sigma_l_0 = sort!(info_parameters[info_parameters.attribute .== "sigma_l", :])
        sigma_l   = Dict(sigma_l_0.commodity .=> sigma_l_0.value)

    #) sigma_z(k)  elasticity of substitution (in LIVESTOCK production) across commodities used as feed for producing commodity k
        sigma_z_0 = sort!(info_parameters[info_parameters.attribute .== "sigma_z", :])
        sigma_z   = Dict(sigma_z_0.commodity .=> sigma_z_0.value)

    #) sigma_w(k)  elasticity of substitution (in LIVESTOCK production) between domestic and imported commodities used as feed for producing commodity k
        sigma_w_0 = sort!(info_parameters[info_parameters.attribute .== "sigma_w", :])
        sigma_w   = Dict(sigma_w_0.commodity .=> sigma_w_0.value)

#  --------------------------------------------------------------------------------------------------

# 2) Elasticities of transformation
  
    #) omega_q(k)  elasticity of transformation (in supply) between current and stored supply of commodity k
        omega_q_0 = sort!(info_exogenous[info_exogenous.attribute .== "omega_q", :])
        omega_q   = Dict(omega_q_0.commodity .=> omega_q_0.value)

    #) omega_s(k)  elasticity of transformation (in supply) between domestic and exported supply of commodity k
        omega_s_0 = sort!(info_parameters[info_parameters.attribute .== "omega_s", :])
        omega_s   = Dict(omega_s_0.commodity .=> omega_s_0.value)

    #) omega_c(k)  elasticity of transformation (in supply) among food, feed and crushing uses of commodity k
        omega_c_0 = sort!(info_exogenous[info_exogenous.attribute .== "omega_c", :])
        omega_c   = Dict(omega_c_0.commodity .=> omega_c_0.value)


#  --------------------------------------------------------------------------------------------------
# PART C: EXOGENOUS INFORMATION
#  --------------------------------------------------------------------------------------------------

    local  PW0_0, PW0, GDP_pc0_0, GDP_pc0, pop0_0, pop0, Pnld0_0, Pnld0, P_NA0_0, P_NA0, epsilon_q_0, epsilon_q, P_NO_FEED0_0, P_NO_FEED0,
           epsilon_l_0, epsilon_l, inv_liv_0, inv_liv, slt_liv_0, slt_liv 

    #) PW(k)       World price of commodity k (Million USD per 1,000 units)
        PW0_0     = sort!(info_exogenous[info_exogenous.attribute .== "International Price", :])
        PW0       = Dict(PW0_0.commodity .=> PW0_0.value)

    #) GDP_pc0(r)  GDP per capita of region r (USD of 2015 per habitant)
        GDP_pc0_0 = sort!(info_exogenous[info_exogenous.attribute .== "GDP per capita", :])
        GDP_pc0   = Dict(GDP_pc0_0.region .=> GDP_pc0_0.value)  

    #) pop0(r)     Population of region r (1,000 habitants)
        pop0_0    = sort!(info_exogenous[info_exogenous.attribute .== "Population", :])
        pop0      = Dict(pop0_0.region .=> pop0_0.value)  

    #) Pnld0(r)    Price of Non-land bundle in region r
        Pnld0_0   = sort!(info_exogenous[info_exogenous.attribute .== "Price of No Land Input", :])
        Pnld0     = Dict(Pnld0_0.region .=> Pnld0_0.value) 

    #) P_NA0(r)    Price of Non-agricultural commodities in region r
        P_NA0_0   = sort!(info_exogenous[info_exogenous.attribute .== "Price of No AG", :])
        P_NA0     = Dict(P_NA0_0.region .=> P_NA0_0.value)   
      
    #) epsilon_q(k)  Price elasticity (of demand) of ending stocks of commodity k
        epsilon_q_0 = sort!(info_exogenous[info_exogenous.attribute .== "epsilon_q", :])  
        epsilon_q   = Dict(epsilon_q_0.commodity .=> epsilon_q_0.value)        

    #) P_NO_FEED0(r,k)  Price of Non-FEED commodities to produce livestock commodity k
        P_NO_FEED0_0 = sort!(info_exogenous[info_exogenous.attribute .== "P_NO_FEED", :])  
        P_NO_FEED0   = Dict((row.region, row.commodity) => row.value  for row in eachrow(P_NO_FEED0_0))   

    #) epsilon_l   Price elasticity (of supply) of land
        epsilon_l_0 = sort!(info_exogenous[info_exogenous.attribute .== "epsilon_l", :])  
        epsilon_l   = epsilon_l_0[:,:value][1]

    #) inv_liv(r,k)  Inventory of livestock commodity k in region r (in 1,000 animals)
        inv_liv_0 = sort!(info_exogenous[info_exogenous.attribute .== "inv_liv", :])  
        inv_liv   = Dict((row.region, row.commodity) => row.value  for row in eachrow(inv_liv_0))   

    #) slt_liv(r,k)  Slaughter of livestock commodity k in region r (in 1,000 animals)
        slt_liv_0 = sort!(info_exogenous[info_exogenous.attribute .== "slt_liv", :])  
        slt_liv   = Dict((row.region, row.commodity) => row.value  for row in eachrow(slt_liv_0))   


#  --------------------------------------------------------------------------------------------------
# PART D: INITIAL LEVEL OF SHOCK VARIABLES 
#  --------------------------------------------------------------------------------------------------

    local  alpha0_0, alpha0, tau_x0_0, tau_x0, tau_m0_0, tau_m0, NTM_exp0_0, NTM_exp0, NTM_imp0_0, NTM_imp0, theta0_0, theta0, 
           Lnd_Schk0_0, Lnd_Schk0, omega_VA0_0, omega_VA0, omega_IN0_0, omega_LIV0_0, omega_LIV0   

    #) alpha0(r)    Ag expenditure share in BSAT commodities in region r (in percent)
        alpha0_0  = sort!(info_exogenous[info_exogenous.attribute .== "Ag Expenditure Share", :])
        alpha0    = Dict(alpha0_0.region .=> alpha0_0.value) 

    #) tau_x0(r,k)  advalorem export tax (or subsidy) for exporting commodity k from region r
        tau_x0_0  = sort!(info_exogenous[info_exogenous.attribute .== "Export tax", :])
        tau_x0    = Dict((row.region, row.commodity) => row.value  for row in eachrow(tau_x0_0))    

    #) tau_m0(r,k)  advalorem import tariff for importing commodity k in region r 
        tau_m0_0  = sort!(info_exogenous[info_exogenous.attribute .== "Import tariff", :])
        tau_m0    = Dict((row.region, row.commodity) => row.value  for row in eachrow(tau_m0_0))   

    #) NTM_exp0(r,k) Non-Tariff Measure for exporting commodity k from region r
        NTM_exp0_0  = sort!(info_exogenous[info_exogenous.attribute .== "NTM for exporting a product", :])
        NTM_exp0    = Dict((row.region, row.commodity) => row.value  for row in eachrow(NTM_exp0_0))   

    #) NTM_imp0(r,k) Non Tariff Measure for importing commodity k in region r
        NTM_imp0_0  = sort!(info_exogenous[info_exogenous.attribute .== "NTM for importing a product", :])
        NTM_imp0    = Dict((row.region, row.commodity) => row.value  for row in eachrow(NTM_imp0_0)) 

    #) theta0(r,k)   Land productivity shock in the production of PRIMARY commodity k in region r
        theta0_0  = sort!(info_exogenous[info_exogenous.attribute .== "Land Productivity", :])
        theta0    = Dict((row.region, row.commodity) => row.value  for row in eachrow(theta0_0))  

    #) Lnd_Schk0(r)  Land supply unavailability in region r
        Lnd_Schk0_0 = sort!(info_exogenous[info_exogenous.attribute .== "Land Unavailability ", :])
        Lnd_Schk0   = Dict(Lnd_Schk0_0.region .=> Lnd_Schk0_0.value)   

    #) omega_VA0(r,k)   TFP shock to the value added in the production of PRIMARY commodity k in region r       
        omega_VA0_0 = sort!(info_exogenous[info_exogenous.attribute .== "TFP Productivity Value Added", :])
        omega_VA0   = Dict((row.region, row.commodity) => row.value  for row in eachrow(omega_VA0_0))   

    #) omega_IN0(r,k)   TFP shock to intermediate inputs used in the production of SECONDARY commodity k in region r
        omega_IN0_0 = sort!(info_exogenous[info_exogenous.attribute .== "TFP Productivity Intermediates", :])
        omega_IN0   = Dict((row.region, row.commodity) => row.value  for row in eachrow(omega_IN0_0))  

    #) omega_LIV0(r,k)  TFP shock to feed use in the production of Livestock commodity k in region r
        omega_LIV0_0 = sort!(info_exogenous[info_exogenous.attribute .== "TFP Productivity Feed Use", :])
        omega_LIV0   = Dict((row.region, row.commodity) => row.value  for row in eachrow(omega_LIV0_0))  


#  --------------------------------------------------------------------------------------------------
# PART E: USDA PROJECTIONS
#  --------------------------------------------------------------------------------------------------

    local  USDA_Proj_Dict_to_DF, Target_A_0_USDA, Target_A_USDA, Target_A, Target_A_df, Bgstock0_0_USDA, Bgstock0_USDA, Target_BS, 
           Target_BS_df, Target_Q_0_USDA, Target_Q_USDA, Target_Q, Target_Q_df, Target_M_0_USDA, Target_M_USDA, Target_M, Target_M_df, 
           Target_DC_0_USDA, Target_DC_USDA, Target_DC, Target_DC_df, Target_DC_FOOD_0_USDA, Target_DC_FOOD_USDA, Target_DC_FOOD, 
           Target_DC_FOOD_df, Target_DC_FEED_0_USDA, Target_DC_FEED_USDA, Target_DC_FEED, Target_DC_FEED_df, Target_Crsh_0_USDA, 
           Target_Crsh_USDA, Target_Crsh, Target_Crsh_df, Target_X_0_USDA, Target_X_USDA, Target_X, Target_X_df, EdngStock0_0_USDA, 
           EdngStock0_USDA, Target_ES, Target_ES_df, Loss0_0_USDA, Loss0_USDA, Target_Loss, Target_Loss_df, Target_Y_0_USDA, Target_Y_USDA, 
           Target_Y, Target_Y_df, Target_E_Q0_USDA, Target_E_Cr0_USDA, Target_E_0_USDA, Target_E_USDA, Target_E, Target_E_df, Feed_DA_Liv0_0_USDA, 
           Feed_DA_Liv_0_USDA, Feed_DA_Liv, Feed_DA_Liv_df, DC_FEED_LIV_df, DC_FEED_LIV, DC_FEED_OTR_0, DC_FEED_OTR_1, DC_FEED_OTR_2, DC_FEED_OTR_df, 
           DC_FEED_OTR, Z_LIV_Feed_0_df, Z_LIV_Feed_0, Dscrp_Cons, Dicts_Cons, Dscrp_Cons_EP_0, Dscrp_Cons_EP_1, Max_Dscrp_Cons_EP, Dscrp_Mkt, 
           Dscrp_Mkt_0, Dscrp_Mkt_1, Max_Dscrp_Mkt_EP, Total_Sources, Target_M_FOOD, Target_M_FOOD_df, Target_M_FEED_LIV, Target_M_FEED_LIV_df, 
           Target_M_FEED_OTR, Target_M_FEED_OTR_df, Target_M_CRUSH, Target_M_CRUSH_df, Target_M_OTHR, Target_M_OTHR_df, Target_M_FEED_LIV_comm,
           Target_M_FEED_LIV_comm_df, Dscrp_IMP_0, Dscrp_IMP_1, Max_Dscrp_IMP_EP


    #) Function: transforms a dictionary into a dataframe
        function USDA_Proj_Dict_to_DF(dict)
            return sort!(DataFrame([(k[1], k[2], v) for (k, v) in dict], [:region, :commodity, :value]))
        end   


#1) Observed data

    #) Target_A(r,k)   target harvested area of primary commodity k in region r 
        Target_A_0_USDA    = sort!(info_targets[info_targets.attribute .== "Area", :])
        Target_A_USDA      = Dict((row.region, row.commodity) => row.value  for row in eachrow(Target_A_0_USDA))    
        Target_A           = Dict(k => ismissing(v) ? 0.0 : Float64(v) for (k, v) in deepcopy(Target_A_USDA))
        Target_A_df        = USDA_Proj_Dict_to_DF(Target_A)

    #) Bgstock0(r,k)   target beginning stocks of commodity k in region r 
        Bgstock0_0_USDA    = sort!(info_targets[info_targets.attribute .== "Beginning Stocks", :])
        Bgstock0_USDA      = Dict((row.region, row.commodity) => row.value for row in eachrow(Bgstock0_0_USDA))              
        Target_BS          = Dict(k => ismissing(v) ? 0.0 : Float64(v) for (k, v) in deepcopy(Bgstock0_USDA))      
        Target_BS_df       = USDA_Proj_Dict_to_DF(Target_BS)

    #) Target_Q(r,k)   target production of commodity k in region r 
        Target_Q_0_USDA    = sort!(info_targets[info_targets.attribute .== "Production", :])
        Target_Q_USDA      = Dict((row.region, row.commodity) => row.value  for row in eachrow(Target_Q_0_USDA))   
        Target_Q           = Dict(k => ismissing(v) ? 0.0 : Float64(v) for (k, v) in deepcopy(Target_Q_USDA))
        Target_Q_df        = USDA_Proj_Dict_to_DF(Target_Q)

    #) Target_M(r,k)   target imports of commodity k in region r   
        Target_M_0_USDA    = sort!(info_targets[info_targets.attribute .== "Imports", :])
        Target_M_USDA      = Dict((row.region, row.commodity) => row.value  for row in eachrow(Target_M_0_USDA)) 
        Target_M           = Dict(k => ismissing(v) ? 0.0 : Float64(v) for (k, v) in deepcopy(Target_M_USDA))
        Target_M_df        = USDA_Proj_Dict_to_DF(Target_M)  

    #) Target_DC(r,k)  target total consumption of commodity k in region r 
        Target_DC_0_USDA   = sort!(info_targets[info_targets.attribute .== "Total Consumption", :])
        Target_DC_USDA     = Dict((row.region, row.commodity) => row.value  for row in eachrow(Target_DC_0_USDA))    
        Target_DC          = Dict(k => ismissing(v) ? 0.0 : Float64(v) for (k, v) in deepcopy(Target_DC_USDA))
        Target_DC_df       = USDA_Proj_Dict_to_DF(Target_DC)   

    #) Target_DC_FOOD(r,k)  target FOOD consumption of every commodity k in region r 
        Target_DC_FOOD_0_USDA   = sort!(info_targets[info_targets.attribute .== "Food Consumption", :])
        Target_DC_FOOD_USDA     = Dict((row.region, row.commodity) => row.value  for row in eachrow(Target_DC_FOOD_0_USDA))    
        Target_DC_FOOD          = Dict(k => ismissing(v) ? 0.0 : Float64(v) for (k, v) in deepcopy(Target_DC_FOOD_USDA))
        Target_DC_FOOD_df       = USDA_Proj_Dict_to_DF(Target_DC_FOOD)

    #) Target_DC_FEED(r,k)  target FEED consumption used as FEED for producing LIVESTOCK commodity k in region r
        Target_DC_FEED_0_USDA   = sort!(info_targets[info_targets.attribute .== "Feed Consumption", :])
        Target_DC_FEED_USDA     = Dict((row.region, row.commodity) => row.value  for row in eachrow(Target_DC_FEED_0_USDA))   
        Target_DC_FEED          = Dict(k => ismissing(v) ? 0.0 : Float64(v) for (k, v) in deepcopy(Target_DC_FEED_USDA)) 
        Target_DC_FEED_df       = USDA_Proj_Dict_to_DF(Target_DC_FEED)

    #) Target_Crsh(r,k)   target crush of input-commodity k in region r 
        Target_Crsh_0_USDA = sort!(info_targets[info_targets.attribute .== "Crushing", :])
        Target_Crsh_USDA   = Dict((row.region, row.commodity) => row.value  for row in eachrow(Target_Crsh_0_USDA))  
        Target_Crsh        = Dict(k => ismissing(v) ? 0.0 : Float64(v) for (k, v) in deepcopy(Target_Crsh_USDA))
        Target_Crsh_df     = USDA_Proj_Dict_to_DF(Target_Crsh)

    #) Target_X(r,k)   target exports of commodity k from every region r          
        Target_X_0_USDA    = sort!(info_targets[info_targets.attribute .== "Exports", :])
        Target_X_USDA      = Dict((row.region, row.commodity) => row.value  for row in eachrow(Target_X_0_USDA))  
        Target_X           = Dict(k => ismissing(v) ? 0.0 : Float64(v) for (k, v) in deepcopy(Target_X_USDA))
        Target_X_df        = USDA_Proj_Dict_to_DF(Target_X)

    #) EdngStock0(r,k)  target ending stocks of commodity k in region r 
        EdngStock0_0_USDA  = sort!(info_targets[info_targets.attribute .== "Ending Stocks", :])
        EdngStock0_USDA    = Dict((row.region, row.commodity) => row.value  for row in eachrow(EdngStock0_0_USDA))         
        Target_ES          = Dict(k => ismissing(v) ? 0.0 : Float64(v) for (k, v) in deepcopy(EdngStock0_USDA))  
        Target_ES_df       = USDA_Proj_Dict_to_DF(Target_ES)

    #) Loss0(r,k)  target uncounted losses of commodity k in region r 
        Loss0_0_USDA       = sort!(info_targets[info_targets.attribute .== "Loss", :])
        Loss0_USDA         = Dict((row.region, row.commodity) => row.value  for row in eachrow(Loss0_0_USDA))   
        Target_Loss        = Dict(k => ismissing(v) ? 0.0 : Float64(v) for (k, v) in deepcopy(Loss0_USDA))
        Target_Loss_df     = USDA_Proj_Dict_to_DF(Target_Loss)     

    #) Target_Y(r,k)   target yields of commodity k in region r   
        Target_Y_0_USDA    = sort!(info_targets[info_targets.attribute .== "Yields", :])
        Target_Y_USDA      = Dict((row.region, row.commodity) => row.value  for row in eachrow(Target_Y_0_USDA))  
        Target_Y           = deepcopy(Target_Y_USDA)
        Target_Y_df        = USDA_Proj_Dict_to_DF(Target_Y)

    #) Target_E(r,k)   target extraction rate to produce secondary commodity k in region r 
        Target_E_Q0_USDA   = sort!(Target_Q_df[(Target_Q_df.commodity .== "SoyOil") .| (Target_Q_df.commodity .== "SoyMeal"), :])
            rename!(Target_E_Q0_USDA,  :value => :DA_crush) 
        Target_E_Cr0_USDA  = sort!(Target_Crsh_df[:, [:region, :value]])
            rename!(Target_E_Cr0_USDA, :value => :SA_crush) 
        Target_E_0_USDA    = outerjoin(Target_E_Q0_USDA, Target_E_Cr0_USDA, on = [:region]) 
        Target_E_0_USDA.SA_crush = coalesce.(Target_E_0_USDA.SA_crush, 0)
        #print(Target_E_0_USDA)
        Target_E_0_USDA.value    = (Target_E_0_USDA.DA_crush./Target_E_0_USDA.SA_crush).*100
        #print(Target_E_0_USDA)
        filter!(Target_E_0_USDA -> !ismissing(Target_E_0_USDA.value) && !isnan(Target_E_0_USDA.value), Target_E_0_USDA)
        Target_E_USDA      = Dict((row.region, row.commodity) => row.value  for row in eachrow(Target_E_0_USDA)) 
        Target_E           = deepcopy(Target_E_USDA)
        Target_E_df        = USDA_Proj_Dict_to_DF(Target_E)

    #) Feed_DA_Liv0(r,k,g)  Demand of input-commodity g for feeding livestock commodity k in region r
        Feed_DA_Liv0_0_USDA  = sort!(info_targets[info_targets.attribute .== "Total_feed_use_input_to_commodity", :])
        Feed_DA_Liv_0_USDA   = Dict((row.region, row.commodity, row.input) => row.value  for row in eachrow(Feed_DA_Liv0_0_USDA)) 
        Feed_DA_Liv          = Dict(k => ismissing(v) ? 0.0 : Float64(v) for (k, v) in deepcopy(Feed_DA_Liv_0_USDA)) 
        Feed_DA_Liv_df       = sort!(DataFrame([(k[1], k[2], k[3], v) for (k, v) in Feed_DA_Liv], [:region, :commodity, :input, :value]))

#  --------------------------------------------------------------------------------------------------

#2) Feed Consumption disaggregation 

    #) DC_FEED_LIV(r,k)  Feed consumption of commodity k for feeding USDA livestock in region r
        DC_FEED_LIV_df = combine(groupby(Feed_DA_Liv_df, [:region, :input]), :value => sum)
            rename!(DC_FEED_LIV_df, :value_sum => :value)
            rename!(DC_FEED_LIV_df, :input     => :commodity)
        DC_FEED_LIV    =Dict((row.region, row.commodity) => row.value  for row in eachrow(DC_FEED_LIV_df))

    #) DC_FEED_OTR(r,k)  Feed consumption of commodity k for feeding OTHER livestock in region r
        DC_FEED_OTR_0 = deepcopy(Target_DC_FEED_df)
            rename!(DC_FEED_OTR_0, :value => :Feed_ALL_LIV)
        DC_FEED_OTR_1 = deepcopy(DC_FEED_LIV_df)
            rename!(DC_FEED_OTR_1, :value => :Feed_USDA_LIV)
        DC_FEED_OTR_2 =leftjoin(DC_FEED_OTR_0, DC_FEED_OTR_1, on = [:region, :commodity])
        # NOTE: the "leftjoin" ensures that all region–commodity pairs are defined exclusively by `Target_DC_FEED_df`. Looking at the data, we observe that an
        #           "outerjoin" introduces additional pairs with feed values equal to zero, which is expected since those pairs do not exist in the data.
            DC_FEED_OTR_2.Feed_ALL_LIV  = coalesce.(DC_FEED_OTR_2.Feed_ALL_LIV, 0.0)
            DC_FEED_OTR_2.Feed_USDA_LIV = coalesce.(DC_FEED_OTR_2.Feed_USDA_LIV, 0.0)
        DC_FEED_OTR_2.value = DC_FEED_OTR_2.Feed_ALL_LIV .- DC_FEED_OTR_2.Feed_USDA_LIV
        DC_FEED_OTR_df = DC_FEED_OTR_2[:,[:region, :commodity, :value]] 
        DC_FEED_OTR    = Dict((row.region, row.commodity) => row.value  for row in eachrow(DC_FEED_OTR_df))

    #) Z_LIV_Feed_0(r,k) Total demand of livestock commodity k of feed inputs in region r
        Z_LIV_Feed_0_df = combine(groupby(Feed_DA_Liv_df, [:region, :commodity]), :value => sum)
             rename!(Z_LIV_Feed_0_df, :value_sum => :value)
        Z_LIV_Feed_0    = Dict((row.region, row.commodity) => row.value  for row in eachrow(Z_LIV_Feed_0_df))

#  --------------------------------------------------------------------------------------------------

#3) Decimal adjustments 

    #NOTE: The model uses observed total consumption data by category to disaggregate import values across categories. This requires that
    #      total consumption MUST MATCH EXACTLY the sum of consumption across all categories to avoid numerical issues. Additionally, total 
    #      supply MUST MATCH EXACTLY total demand to ensure that the model does not encounter numerical problems arising from starting in a 
    #      non-equilibrium state. We therefore check the following conditions: 
    #       (a) ∑ DC_i = DC 
    #       (b) Supply = Demand 
    #
    #      If condition (a) is not satisfied, the residual difference is allocated to the consumption category with the largest value.
    #      If condition (b) is not satisfied, the residual difference is allocated to ending stocks.

    #a) ∑ DC_i = DC   
    #NOTE: The assumption is that aggregate total consumption corresponds to the true value.
        Dscrp_Cons  = Dict(k => get(Target_DC, k, 0.0) - (get(Target_DC_FOOD, k, 0.0) + get(DC_FEED_LIV, k, 0.0) + get(DC_FEED_OTR, k, 0.0) + get(Target_Crsh, k, 0.0))   
                      for k in  union(keys(Target_DC), keys(Target_DC_FOOD), keys(DC_FEED_LIV), keys(DC_FEED_OTR), keys(Target_Crsh)) )

        Dicts_Cons  = [Target_DC_FOOD, DC_FEED_LIV, DC_FEED_OTR, Target_Crsh]

            for k in keys(Dscrp_Cons)
                local Δ
                Δ = Dscrp_Cons[k]
                # Only minimal discrepancies are adjusted
                if -2.0 <= Δ <= 2.0
                    local  vals_with_idx, dict_idx, maxidx
                    vals_with_idx = [(get(d, k, missing), i) for (i, d) in pairs(Dicts_Cons) 
                                    if !ismissing(get(d, k, missing))]
                    if !isempty(vals_with_idx)
                        maxval, maxidx = findmax(first.(vals_with_idx))  
                        dict_idx = last(vals_with_idx[ maxidx ]) 
                        Dicts_Cons[dict_idx][k] = get(Dicts_Cons[dict_idx], k, 0.0) + Δ
                    end
                end
            end

        #) Checking adjustment
            Dscrp_Cons_EP_0  = Dict(k => get(Target_DC, k, 0.0) - (get(Target_DC_FOOD, k, 0.0) + get(DC_FEED_LIV, k, 0.0) + get(DC_FEED_OTR, k, 0.0) + get(Target_Crsh, k, 0.0))   
                               for k in  union(keys(Target_DC), keys(Target_DC_FOOD), keys(DC_FEED_LIV), keys(DC_FEED_OTR), keys(Target_Crsh)) )
        
            Dscrp_Cons_EP_1  = USDA_Proj_Dict_to_DF(Dscrp_Cons_EP_0)
            Max_Dscrp_Cons_EP= maximum(Dscrp_Cons_EP_1.value)

        #) Adjusting the corresponding dataframes
            Target_DC_FOOD_df  = USDA_Proj_Dict_to_DF(Target_DC_FOOD)
            Target_Crsh_df     = USDA_Proj_Dict_to_DF(Target_Crsh)
            DC_FEED_LIV_df     = USDA_Proj_Dict_to_DF(DC_FEED_LIV)
            DC_FEED_OTR_df     = USDA_Proj_Dict_to_DF(DC_FEED_OTR)

            
    #b) Supply = Demand
        Dscrp_Mkt  = Dict(k => ((get(Target_BS, k, 0.0) + get(Target_Q, k, 0.0) + get(Target_M, k, 0.0)) - get(Target_Loss, k, 0.0)) - (get(Target_DC, k, 0.0) + get(Target_X, k, 0.0) + get(Target_ES, k, 0.0))   
                     for k in  union(keys(Target_BS), keys(Target_Q), keys(Target_M), keys(Target_Loss), keys(Target_DC), keys(Target_X), keys(Target_ES) ))

        Dicts_Mkt  = [Target_BS, Target_Q, Target_M]

            for k in keys(Dscrp_Mkt)
                local Δ_m
                Δ_m = Dscrp_Mkt[k]
                # Only minimal discrepancies are adjusted
                if -2.0 <= Δ_m <= 2.0
                    local  vals_with_idx_mkt, dict_idx_mkt, maxidx_mkt
                    vals_with_idx_mkt = [(get(d, k, missing), i) for (i, d) in pairs(Dicts_Mkt) 
                                    if !ismissing(get(d, k, missing))]
                    if !isempty(vals_with_idx_mkt)
                        maxval, maxidx_mkt = findmax(first.(vals_with_idx_mkt))  
                        dict_idx_mkt = last(vals_with_idx_mkt[ maxidx_mkt]) 
                        Dicts_Mkt[dict_idx_mkt][k] = get(Dicts_Mkt[dict_idx_mkt], k, 0.0) - Δ_m
                    end
                end
            end      

        #) Checking adjustment
            Dscrp_Mkt_0     = Dict(k => ((get(Target_BS, k, 0.0) + get(Target_Q, k, 0.0) + get(Target_M, k, 0.0)) - get(Target_Loss, k, 0.0)) - (get(Target_DC, k, 0.0) + get(Target_X, k, 0.0) + get(Target_ES, k, 0.0))   
                              for k in  union(keys(Target_BS), keys(Target_Q), keys(Target_M), keys(Target_Loss), keys(Target_DC), keys(Target_X), keys(Target_ES)))
            Dscrp_Mkt_1     = USDA_Proj_Dict_to_DF(Dscrp_Mkt_0)
            Max_Dscrp_Mkt_EP= maximum(Dscrp_Mkt_1.value)

        #) Adjusting the corresponding dataframes
            Target_BS_df    = USDA_Proj_Dict_to_DF(Target_BS)
            Target_Q_df     = USDA_Proj_Dict_to_DF(Target_Q)
            Target_M_df     = USDA_Proj_Dict_to_DF(Target_M)

        #) Updating: Extraction Rate
        Target_E_Q0_USDA   = sort!(Target_Q_df[(Target_Q_df.commodity .== "SoyOil") .| (Target_Q_df.commodity .== "SoyMeal"), :])   
            rename!(Target_E_Q0_USDA,  :value => :DA_crush) 
        Target_E_Cr0_USDA  = sort!(Target_Crsh_df[:, [:region, :value]])
            rename!(Target_E_Cr0_USDA, :value => :SA_crush) 
        Target_E_0_USDA    = outerjoin(Target_E_Q0_USDA, Target_E_Cr0_USDA, on = [:region]) 
        Target_E_0_USDA.SA_crush = coalesce.(Target_E_0_USDA.SA_crush, 0)
        #print(Target_E_0_USDA)
        Target_E_0_USDA.value    = (Target_E_0_USDA.DA_crush./Target_E_0_USDA.SA_crush).*100
        #print(Target_E_0_USDA)
        filter!(Target_E_0_USDA -> !ismissing(Target_E_0_USDA.value) && !isnan(Target_E_0_USDA.value), Target_E_0_USDA)
        Target_E_USDA      = Dict((row.region, row.commodity) => row.value  for row in eachrow(Target_E_0_USDA)) 
        Target_E           = deepcopy(Target_E_USDA)   
        Target_E_df        = USDA_Proj_Dict_to_DF(Target_E)

#  --------------------------------------------------------------------------------------------------

#4) Proportional imputation for disaggregating total imports

    #) Total_Sources(r,k)   Total target sources in supply of commodity k in region r
        Total_Sources      = Dict(k => (BigFloat(get(Target_BS, k, 0.0)) + BigFloat(get(Target_Q, k, 0.0)) + BigFloat(get(Target_M, k, 0.0))) - BigFloat(get(Target_Loss, k, 0.0)) 
                             for k in union(keys(Target_BS), keys(Target_Q), keys(Target_M), keys(Target_Loss)))     

    #) Target_M_FOOD(r,k)   Target FOOD imports of commodity k in region r 
        Target_M_FOOD      = Dict(k => BigFloat(get(Target_DC_FOOD,k, 0.0))   * (BigFloat(get(Target_M, k, 0.0))/BigFloat(get(Total_Sources, k, 0.0))) for k in keys(Target_M))
        Target_M_FOOD_df   = USDA_Proj_Dict_to_DF(Target_M_FOOD)

    #) Target_M_FEED_LIV(r,k)   Target FEED imports of commodity k in region r used as FEED for feeding USDA livestock
        Target_M_FEED_LIV      = Dict(k => BigFloat(get(DC_FEED_LIV, k, 0.0)) * (BigFloat(get(Target_M, k, 0.0))/BigFloat(get(Total_Sources, k, 0.0))) for k in keys(Target_M))
        Target_M_FEED_LIV_df   = USDA_Proj_Dict_to_DF(Target_M_FEED_LIV)

    #) Target_M_FEED_OTR(r,k)   Target FEED imports of commodity k in region r used as FEED for feeding OTHER livestock 
        Target_M_FEED_OTR      = Dict(k => BigFloat(get(DC_FEED_OTR, k, 0.0)) * (BigFloat(get(Target_M, k, 0.0))/BigFloat(get(Total_Sources, k, 0.0))) for k in keys(Target_M))
        Target_M_FEED_OTR_df   = USDA_Proj_Dict_to_DF(Target_M_FEED_OTR)

    #) Target_M_CRUSH(r,k)  Target imports for crushing of commodity k in region r  
        Target_M_CRUSH     = Dict(k => BigFloat(get(Target_Crsh, k, 0.0))    *  (BigFloat(get(Target_M, k, 0.0))/BigFloat(get(Total_Sources, k, 0.0))) for k in keys(Target_M))
        Target_M_CRUSH_df  = USDA_Proj_Dict_to_DF(Target_M_CRUSH)

    #) Target_M_OTHR(r,k)   Target OTHER imports of every k in region r  
        Target_M_OTHR     = Dict(k => (BigFloat(get(Target_X, k, 0.0)) + BigFloat(get(Target_ES, k, 0.0))) * (BigFloat(get(Target_M, k, 0.0))/BigFloat(get(Total_Sources, k, 0.0))) for k in keys(Target_M))
        Target_M_OTHR_df  = USDA_Proj_Dict_to_DF(Target_M_OTHR)        

    #) Target_M_FEED_LIV_comm(r,k,g) Target FEED imports of commodity g in region r used as FEED for feeding LIVESTOCK commodity k
        Target_M_FEED_LIV_comm    = Dict((r,k,g) => Feed_DA_Liv[(r,k,g)] * (BigFloat(get(Target_M, (r,g), 0.0)) /  BigFloat(get(Total_Sources, (r,g), 0.0))) for (r,k,g) in keys(Feed_DA_Liv) if haskey(Target_M, (r,g)))   
        Target_M_FEED_LIV_comm_df = sort!(DataFrame([(k[1], k[2], k[3], v) for (k, v) in Target_M_FEED_LIV_comm], [:region, :commodity, :input, :value]))

        #) Checking that disaggregated imports match aggregate imports
            Dscrp_IMP_0     = Dict(k => get(Target_M, k, 0.0) - (get(Target_M_FOOD, k, 0.0) + get(Target_M_FEED_LIV, k, 0.0) + get(Target_M_FEED_OTR, k, 0.0) + get(Target_M_CRUSH, k, 0.0) + get(Target_M_OTHR, k, 0.0))   
                                 for k in  union(keys(Target_M), keys(Target_M_FOOD), keys(Target_M_FEED_LIV), keys(Target_M_FEED_OTR), keys(Target_M_CRUSH), keys(Target_M_OTHR)) )
            Dscrp_IMP_1     = USDA_Proj_Dict_to_DF(Dscrp_IMP_0)
            Max_Dscrp_IMP_EP= maximum(Dscrp_IMP_1.value)
       

#  --------------------------------------------------------------------------------------------------
# PART F: CHECKING MARKET CLEARING CONDITIONS  
#  --------------------------------------------------------------------------------------------------

    local  Supply_Balance_Mkt, Demand_Balance_Mkt, df_Supply_Balance_Mkt, df_Demand_Balance_Mkt, df_Market, Max_DIF_Balance, Consumption_DAg, 
           df_Consumption_DAg, df_Consumption, Max_Cons_Balance, Imports_DAg, df_Imports_DAg, df_Imports, Max_Imp_Balance 
        

    #1) Status: Market of every commodity k in region k
  
        #) Supply
        Supply_Balance_Mkt    = Dict(k => (get(Target_BS, k, 0.0) + get(Target_Q, k, 0.0) + get(Target_M, k, 0.0)) - get(Target_Loss, k, 0.0)   
                                for k in  union(keys(Target_BS), keys(Target_Q), keys(Target_M), keys(Target_Loss)))
        df_Supply_Balance_Mkt = sort!(DataFrame([(k[1], k[2], v) for (k, v) in Supply_Balance_Mkt], [:region, :commodity, :supply]))

        #) Demand
        Demand_Balance_Mkt    = Dict(k => get(Target_DC, k, 0.0) + get(Target_X, k, 0.0) + get(Target_ES, k, 0.0)  
                                for k in  union(keys(Target_DC), keys(Target_X), keys(Target_ES)))
        df_Demand_Balance_Mkt = sort!(DataFrame([(k[1], k[2], v) for (k, v) in Demand_Balance_Mkt], [:region, :commodity, :demand]))

        #) Market 
        df_Market         = outerjoin(df_Supply_Balance_Mkt, df_Demand_Balance_Mkt, on = [:region, :commodity])                         
        df_Market.Balance = abs.(df_Market.supply .- df_Market.demand)   
        Max_DIF_Balance   = maximum(df_Market.Balance)
        #print(Max_DIF_Balance)
        #NOTE: The maximum difference is a useful statistic, as it captures the largest deviation. The model uses a threshold of 1e-6 
        #      to determine whether supply equals demand.

                println("-----------------------------------------------------------------------------------------------------------") 

            if Max_DIF_Balance < 1e-6            
                println("All markets:   CLEAR")
                println("               Supply(region,commodity) = Demand(region,commodity) for all combinations (region, commodity)")
                println("  ")
                println("-----------------------------------------------------------------------------------------------------------") 
            else             
                println("All markets:   NOT CLEAR")
                println("               Supply(region,commodity) ≠ Demand(region,commodity) at least in one market (region, commodity)")
                println("  ")
                println("-----------------------------------------------------------------------------------------------------------")                 
            end
  
#  --------------------------------------------------------------------------------------------------

    #2) Status Consumption
        Consumption_DAg        = Dict(k => get(Target_DC_FOOD, k, 0.0) + get(DC_FEED_LIV, k, 0.0) + get(DC_FEED_OTR, k, 0.0) + get(Target_Crsh, k, 0.0)   
                                 for k in  union(keys(Target_DC_FOOD), keys(DC_FEED_LIV), keys(DC_FEED_OTR), keys(Target_Crsh)) )
        df_Consumption_DAg     = sort!(DataFrame([(k[1], k[2], v) for (k, v) in Consumption_DAg], [:region, :commodity, :Consumption_DAg]))

        df_Consumption         = leftjoin(Target_DC_df, df_Consumption_DAg, on = [:region, :commodity]) 
        # NOTE: the "leftjoin" ensures that all region–commodity pairs are defined exclusively by `Target_DC_df`. Looking at the data, we observe that an
        #           "outerjoin" introduces additional pairs with feed values equal to zero, which is expected since those pairs do not exist in the data.               
        df_Consumption.Balance = abs.(df_Consumption.value .- df_Consumption.Consumption_DAg)   
        Max_Cons_Balance       = maximum(df_Consumption.Balance)
        #print(Max_Cons_Balance)
        #NOTE: The maximum difference is a useful statistic, as it captures the largest deviation. The model uses a threshold of 1e-6 
        #      to determine whether total consumption equals the sum of all disaggregated consumptions.

            if Max_Cons_Balance < 1e-6
                println("All markets:   CLEAR")                           
                println("               ∑ Consumption components = Total Consumption - for all combinations (region, commodity)" )
                println("  ")
                println("-----------------------------------------------------------------------------------------------------------") 
            else             
                println("All markets:   NOT CLEAR")                
                println("               ∑ Consumption components ≠ Total Consumption - for all combinations (region, commodity)")
                println("  ")
                println("-----------------------------------------------------------------------------------------------------------")              
            end

#  --------------------------------------------------------------------------------------------------

    #3) Status Imports
        Imports_DAg        = Dict(k => get(Target_M_FOOD, k, 0.0) + get(Target_M_FEED_LIV, k, 0.0) + get(Target_M_FEED_OTR, k, 0.0) + get(Target_M_CRUSH, k, 0.0) + get(Target_M_OTHR, k, 0.0)   
                             for k in  union(keys(Target_M_FOOD), keys(Target_M_FEED_LIV), keys(Target_M_FEED_OTR), keys(Target_M_CRUSH), keys(Target_M_OTHR)))
        df_Imports_DAg     = sort!(DataFrame([(k[1], k[2], v) for (k, v) in Imports_DAg], [:region, :commodity, :Imports_DAg]))

        df_Imports         = leftjoin(Target_M_df, df_Imports_DAg, on = [:region, :commodity])                         
        df_Imports.Balance = abs.(df_Imports.value .- df_Imports.Imports_DAg)   
        Max_Imp_Balance    = maximum(df_Imports.Balance)
        #print(Max_Imp_Balance)
        #NOTE: The maximum difference is a useful statistic, as it captures the largest deviation. The model uses a threshold of 1e-6 
        #      to determine whether total imports equals the sum of all disaggregated imports.

            if Max_Imp_Balance < 1e-6    
                println("All markets:   CLEAR")                        
                println("               ∑ Import components = Total Imports - for all combinations (region, commodity)")
                println("  ")
                println("-----------------------------------------------------------------------------------------------------------") 
            else   
                println("All markets:   NOT CLEAR")                          
                println("               ∑ Import components ≠ Total Imports - for all combinations (region, commodity)")
                println("  ")
                println("-----------------------------------------------------------------------------------------------------------")                 
            end




        #  ----------------------------------------------------  IMPORTANT  ---------------------------------------------------   #  
        #  -------------------------------------------------------- ### --------------------------------------------------------  #
        #  -------------------------------------------------------- ### --------------------------------------------------------  #

        #) NOTE: This condition verifies that all markets and disaggregated variables clear. If not, the remaining code is skipped

                if Max_DIF_Balance > 1e-6 || Max_Cons_Balance > 1e-6 || Max_Imp_Balance > 1e-6
                    println("Baseline Projections Data DO NOT clear in levels")
                    println("No simulation is provided")
                    continue  
                end
           
        #  -------------------------------------------------------- ### --------------------------------------------------------  #  
        #  -------------------------------------------------------- ### --------------------------------------------------------  #
        #  -------------------------------------------------------- ### --------------------------------------------------------  #




#  --------------------------------------------------------------------------------------------------
# PART G: MODEL CONSTRAINTS
#  --------------------------------------------------------------------------------------------------

    local  LC_BSAT_Market_0, LC_BSAT_Market, CUR_SUPL_BSAT_Market_0, CUR_SUPL_BSAT_Market, CUR_SUPL_DOM_BSAT_Market_0, CUR_SUPL_DOM_BSAT_Market, 
           BsStcks_BSAT_Market_0, BsStcks_BSAT_Market, Q_BSAT_Market_0, Q_BSAT_Market, IM_BSAT_Market_0, IM_BSAT_Market, IM_FOOD_BSAT_Market_0, 
           IM_FOOD_BSAT_Market, IM_FEED_BSAT_Market_0, IM_FEED_BSAT_Market, IM_FEED_LIV_BSAT_Market_0, IM_FEED_LIV_BSAT_Market, IM_FEED_OTR_BSAT_Market_0, 
           IM_FEED_OTR_BSAT_Market, IM_FEED_LIV_comm_BSAT_Market_0,  IM_FEED_LIV_comm_BSAT_Market, IM_OTHR_BSAT_Market_0, IM_OTHR_BSAT_Market, 
           IM_CRSH_BSAT_Market_0, IM_CRSH_BSAT_Market, DC_BSAT_Market_0, DC_BSAT_Market, DC_FOOD_BSAT_Market_0, DC_FOOD_BSAT_Market, 
           DC_FOOD_BSAT_Market_BUY_LOC_0, DC_FOOD_BSAT_Market_BUY_LOC, DC_FEED_BSAT_Market_0, DC_FEED_BSAT_Market, DC_FEED_LIV_BSAT_Market_0, 
           DC_FEED_LIV_BSAT_Market, DC_FEED_OTR_BSAT_Market_0, DC_FEED_OTR_BSAT_Market, DC_FEED_OTR_BSAT_Market_BUY_LOC_0, DC_FEED_OTR_BSAT_Market_BUY_LOC, 
           CRSH_BSAT_0, CRSH_BSAT, EX_BSAT_Market_0, EX_BSAT_Market, EndStcks_BSAT_Market_0, EndStcks_BSAT_Market, Loss_BSAT_Market_0, Loss_BSAT_Market, 
           Area_BSAT_Markets_0_a, Area_BSAT_Markets_0_b, Area_BSAT_Markets_0_c, Area_BSAT_Markets_0, Area_BSAT_Markets, Feed_BSAT_Feed_DA_Liv_0, 
           Feed_BSAT_Feed_DA_Liv, Feed_BSAT_Feed_DA_Liv_BUY_LOC_0, Feed_BSAT_Feed_DA_Liv_BUY_LOC, Z_LIV_Feed_BSAT_0,  Z_LIV_Feed_BSAT, Nests_BSAT_Markets_0, 
           Nests_BSAT_Markets_1, Nests_BSAT_Markets_2, Nests_BSAT_Markets_3, Nests_BSAT_Markets

    #) NOTE: The model considers only active markets, defined as those with strictly positive values. However, numerical operations, particularly 
    #        subtractions among variables, may turn exact zeros into small decimal values. This can be problematic, as it may affect the proper 
    #        specification of the constraints. Therefore, a market is considered active if either: (i) baseline projections report a positive value, 
    #        or (ii) its value is not derived from a subtraction of other variables. Otherwise, a threshold of 1e-8 is used to determine whether a 
    #        market is considered active. This mainly applies to markets whose values are computed through subtractions. The threshold is set at
    #        this level to account for small numerical deviations introduced during data adjustments.


    #1) Generation of constraints

        #) LC_BSAT_Market(r,k)       all combinations commodity-region in baseline projections - Supply 
        LC_BSAT_Market_0           = Dict(k => get(Supply_Balance_Mkt, k, 0)  for k in keys(Supply_Balance_Mkt))          
        LC_BSAT_Market             = Dict(k => (v > 0 ? 1 : missing)       for (k, v)  in LC_BSAT_Market_0)
    
        #) CUR_SUPL_BSAT_Market(r,k) all combinations commodity-region in baseline projections - (Supply - ES) Current market supply
        CUR_SUPL_BSAT_Market_0     = Dict(k => get(Supply_Balance_Mkt, k, 0) - get(Target_ES, k, 0)  for k in union(keys(Supply_Balance_Mkt), keys(Target_ES)))
        CUR_SUPL_BSAT_Market       = Dict(k => (v > 1e-8 ? 1 : missing)  for (k, v)  in CUR_SUPL_BSAT_Market_0)

        #) CUR_SUPL_DOM_BSAT_Market(r,k)   all combinations commodity-region in baseline projections - (Supply - ES) - X Current DOMESTIC market supply        
        CUR_SUPL_DOM_BSAT_Market_0 = Dict(k => (get(Supply_Balance_Mkt, k, 0) - get(Target_ES, k, 0)) - get(Target_X, k, 0)  for k in union(keys(Supply_Balance_Mkt), keys(Target_ES), keys(Target_X)))
        CUR_SUPL_DOM_BSAT_Market   = Dict(k => (v > 1e-8 ? 1 : missing)  for (k, v)  in CUR_SUPL_DOM_BSAT_Market_0)

        #) BsStcks_BSAT_Market(r,k)  all combinations commodity-region in baseline projections - Beginning Stocks
        BsStcks_BSAT_Market_0      = Dict(k => get(Target_BS, k, 0.0)   for k in keys(Target_BS)) 
        BsStcks_BSAT_Market        = Dict(k => (v > 0 ? 1 : missing) for (k, v)  in BsStcks_BSAT_Market_0)

        #) Q_BSAT_Market(r,k)        all combinations commodity-region in baseline projections - Production        
        Q_BSAT_Market_0            = Dict(k => get(Target_Q, k, 0)       for k in keys(Target_Q))
        Q_BSAT_Market              = Dict(k => (v > 0 ? 1 : missing)  for (k, v)  in Q_BSAT_Market_0)

        #) IM_BSAT_Market(r,k)       all combinations commodity-region in baseline projections - Imports      
        IM_BSAT_Market_0           = Dict(k => get(Target_M, k, 0.0)     for k in keys(Target_M)) 
        IM_BSAT_Market             = Dict(k => (v > 0 ? 1 : missing)  for (k, v)  in IM_BSAT_Market_0)        

        #) IM_FOOD_BSAT_Market(r,k)  all combinations commodity-region in baseline projections - Food Imports
        IM_FOOD_BSAT_Market_0      = Dict(k => get(Target_M_FOOD, k, 0.0)  for k in keys(Target_M_FOOD)) 
        IM_FOOD_BSAT_Market        = Dict(k => (v > 0 ? 1 : missing)    for (k, v)  in IM_FOOD_BSAT_Market_0)

        #) IM_FEED_BSAT_Market(r,k)  all combinations commodity-region in baseline projections - Feed Imports 
        IM_FEED_BSAT_Market_0      = Dict(k => (get(Target_M_FEED_LIV, k, 0.0) + get(Target_M_FEED_OTR, k, 0.0))  for k in union(keys(Target_M_FEED_LIV), keys(Target_M_FEED_OTR)))
        IM_FEED_BSAT_Market        = Dict(k => (v > 0 ? 1 : missing)  for (k, v)  in IM_FEED_BSAT_Market_0)        

        #) IM_FEED_LIV_BSAT_Market(r,k)  all combinations commodity-region in baseline projections - Feed Imports for feeding USDA livestock
        IM_FEED_LIV_BSAT_Market_0  = Dict(k => get(Target_M_FEED_LIV, k, 0.0)   for k in keys(Target_M_FEED_LIV))
        IM_FEED_LIV_BSAT_Market    = Dict(k => (v > 0 ? 1 : missing)         for (k, v)  in IM_FEED_LIV_BSAT_Market_0)        

        #) IM_FEED_OTR_BSAT_Market(r,k)  all combinations commodity-region in baseline projections - Feed Imports for feeding Other livestock
        IM_FEED_OTR_BSAT_Market_0  = Dict(k => get(Target_M_FEED_OTR, k, 0.0)   for k in keys(Target_M_FEED_OTR))
        IM_FEED_OTR_BSAT_Market    = Dict(k => (v > 1e-8 ? 1 : missing)         for (k, v)  in IM_FEED_OTR_BSAT_Market_0)        

        #) IM_FEED_LIV_comm_BSAT_Market(r,k,g)  all combinations region-commodity-input in baseline projections - Feed Imports of input g for feeding livestock commodities
        IM_FEED_LIV_comm_BSAT_Market_0 = Dict(k => get(Target_M_FEED_LIV_comm, k, 0.0)   for k in keys(Target_M_FEED_LIV_comm)) 
        IM_FEED_LIV_comm_BSAT_Market   = Dict(k => (v > 0 ? 1 : missing)              for (k, v)  in IM_FEED_LIV_comm_BSAT_Market_0)

        #) IM_OTHR_BSAT_Market(r,k)  all combinations commodity-region in baseline projections - Other Imports
        IM_OTHR_BSAT_Market_0      = Dict(k => get(Target_M_OTHR, k, 0) for k in keys(Target_M_OTHR))
        IM_OTHR_BSAT_Market        = Dict(k => (v > 0 ? 1 : missing) for (k, v)  in IM_OTHR_BSAT_Market_0)

        #) IM_CRSH_BSAT_Market(r,k)  all combinations commodity-region in baseline projections - Imports of crushed soybeans
        IM_CRSH_BSAT_Market_0      = Dict(k => get(Target_M_CRUSH, k, 0) for k in keys(Target_M_CRUSH))
        IM_CRSH_BSAT_Market        = Dict(k => (v > 0 ? 1 : missing)  for (k, v)  in IM_CRSH_BSAT_Market_0)

        #) DC_BSAT_Market(r,k)       all combinations commodity-region in baseline projections - Total Consumption 
        DC_BSAT_Market_0           = Dict(k => get(Target_DC, k, 0.0)       for k in keys(Target_DC)) 
        DC_BSAT_Market             = Dict(k => (v > 0 ? 1 : missing)     for (k, v)  in DC_BSAT_Market_0)

        #) DC_FOOD_BSAT_Market(r,k)  all combinations commodity-region in baseline projections - Total Food Consumption 
        DC_FOOD_BSAT_Market_0      = Dict(k => get(Target_DC_FOOD, k, 0.0)  for k in keys(Target_DC_FOOD)) 
        DC_FOOD_BSAT_Market        = Dict(k => (v > 0 ? 1 : missing)     for (k, v)  in DC_FOOD_BSAT_Market_0)

        #) DC_FOOD_BSAT_Market_BUY_LOC(r,k)  all combinations commodity-region in baseline projections - Total Food Consumption supplied exclusively with LOCAL prod
        DC_FOOD_BSAT_Market_BUY_LOC_0  = Dict(k => get(Target_DC_FOOD, k, 0.0) - get(Target_M_FOOD, k, 0.0) for k in union(keys(Target_DC_FOOD),keys(Target_M_FOOD))) 
        DC_FOOD_BSAT_Market_BUY_LOC    = Dict(k => (v > 1e-8 ? 1 : missing)  for (k, v)  in DC_FOOD_BSAT_Market_BUY_LOC_0)

        #) DC_FEED_BSAT_Market(r,k)  all combinations commodity-region in baseline projections - Total Feed Consumption 
        DC_FEED_BSAT_Market_0      = Dict(k => get(Target_DC_FEED, k, 0.0)  for k in keys(Target_DC_FEED))
        DC_FEED_BSAT_Market        = Dict(k => (v > 0 ? 1 : missing)     for (k, v)  in DC_FEED_BSAT_Market_0)

        #) DC_FEED_LIV_BSAT_Market(r,k)  all combinations commodity-region in baseline projections - Total Feed Consumption for feeding USDA livestock
        DC_FEED_LIV_BSAT_Market_0  = Dict(k => get(DC_FEED_LIV, k, 0.0)  for k in keys(DC_FEED_LIV))
        DC_FEED_LIV_BSAT_Market    = Dict(k => (v > 0 ? 1 : missing)  for (k, v)  in DC_FEED_LIV_BSAT_Market_0)
        
        #) DC_FEED_OTR_BSAT_Market(r,k)  all combinations commodity-region in baseline projections - Total Feed Consumption for feeding Other livestock
        DC_FEED_OTR_BSAT_Market_0  = Dict(k => get(DC_FEED_OTR, k, 0.0)  for k in keys(DC_FEED_OTR))
        DC_FEED_OTR_BSAT_Market    = Dict(k => (v > 1e-8 ? 1 : missing)  for (k, v)  in DC_FEED_OTR_BSAT_Market_0)
        
        #) DC_FEED_OTR_BSAT_Market_BUY_LOC(r,k)  all combinations commodity-region in baseline projections -Total Feed Consumption for feeding Other livestock supplied exclusively with LOCAL prod
        DC_FEED_OTR_BSAT_Market_BUY_LOC_0  = Dict(k => get(DC_FEED_OTR, k, 0.0) - get(Target_M_FEED_OTR, k, 0.0) for k in union(keys(DC_FEED_OTR), keys(Target_M_FEED_OTR))) 
        DC_FEED_OTR_BSAT_Market_BUY_LOC    = Dict(k => (v > 1e-8 ? 1 : missing)  for (k, v)  in DC_FEED_OTR_BSAT_Market_BUY_LOC_0)
        
        #) CRSH_BSAT(r,k)            all combinations commodity-region in baseline projections - Total crushed soybeans
        CRSH_BSAT_0                = Dict(k => get(Target_Crsh, k, 0.0)  for k in keys(Target_Crsh)) 
        CRSH_BSAT                  = Dict(k => (v > 0 ? 1 : missing)  for (k, v)  in CRSH_BSAT_0)

        #) EX_BSAT_Market(r,k)       all combinations commodity-region in baseline projections - Exports
        EX_BSAT_Market_0           = Dict(k => get(Target_X, k, 0.0)     for k in keys(Target_X)) 
        EX_BSAT_Market             = Dict(k => (v > 0 ? 1 : missing)  for (k, v)  in EX_BSAT_Market_0)
      
        #) EndStcks_BSAT_Market(r,k) all combinations commodity-region in baseline projections - Ending Stocks
        EndStcks_BSAT_Market_0     = Dict(k => get(Target_ES, k, 0.0)    for k in keys(Target_ES))
        EndStcks_BSAT_Market       = Dict(k => (v > 0 ? 1 : missing)  for (k, v)  in EndStcks_BSAT_Market_0)

        #) Loss_BSAT_Market(r,k)     all combinations commodity-region in baseline projections - Loss
        Loss_BSAT_Market_0         = Dict(k => get(Target_Loss, k, 0)     for k in keys(Target_Loss))
        Loss_BSAT_Market           = Dict(k => (v != 0 ? 1 : missing)  for (k, v)  in Loss_BSAT_Market_0)

        #) Area_BSAT_Markets(r)  all regions in baseline projections - Area
        Area_BSAT_Markets_0_a      = deepcopy(Target_A_df)
        Area_BSAT_Markets_0_b      = combine(groupby(Area_BSAT_Markets_0_a, [:region]), :value => sum)
        Area_BSAT_Markets_0_c      = Dict(Area_BSAT_Markets_0_b.region .=> Area_BSAT_Markets_0_b.value_sum) 
        Area_BSAT_Markets_0        = Dict(k => get(Area_BSAT_Markets_0_c, k, 0) for k in keys(Area_BSAT_Markets_0_c))
        Area_BSAT_Markets          = Dict(k => (v > 0 ? 1 : missing)         for (k, v)  in Area_BSAT_Markets_0)

        #) Feed_BSAT_Feed_DA_Liv(r,k,g)   all combinations region-commodity-input in baseline projections - Total Consumption of commodity g to feed livestock commodity k in region r
        Feed_BSAT_Feed_DA_Liv_0    = Dict(k => get(Feed_DA_Liv, k, 0.0)    for k in keys(Feed_DA_Liv))
        Feed_BSAT_Feed_DA_Liv      = Dict(k => (v > 0 ? 1 : missing)  for (k, v)  in Feed_BSAT_Feed_DA_Liv_0)

        #) Feed_BSAT_Feed_DA_Liv_BUY_LOC(r,k,g)  all combinations region-commodity-input in baseline projections - Total Consumption of commodity g to feed livestock commodity k in region r supplied exclusively with LOCAL prod        
        Feed_BSAT_Feed_DA_Liv_BUY_LOC_0  = Dict(k => get(Feed_DA_Liv, k, 0.0) - get(Target_M_FEED_LIV_comm, k, 0.0) for k in union(keys(Feed_DA_Liv), keys(Target_M_FEED_LIV_comm))) 
        Feed_BSAT_Feed_DA_Liv_BUY_LOC    = Dict(k => (v > 1e-8 ? 1 : missing)  for (k, v)  in Feed_BSAT_Feed_DA_Liv_BUY_LOC_0)

        #) Z_LIV_Feed_BSAT(r,k)  all combinations region-livestock_commodity with feed demand - Total consumption of livestock commodity k in region r
        Z_LIV_Feed_BSAT_0          = Dict(k => get(Z_LIV_Feed_0, k, 0.0)    for k in keys(Z_LIV_Feed_0))
        Z_LIV_Feed_BSAT            = Dict(k => (v > 0 ? 1 : missing)     for (k, v)  in Z_LIV_Feed_BSAT_0)
       
        #) Nests_BSAT_Markets(r,n)  all combinations nest n region r and commodity k for which there is Food Demand 
        Nests_BSAT_Markets_0       = Dict(k => get(Target_DC_FOOD, k, 0) + get(DC_FEED_OTR, k, 0) for k in union(keys(Target_DC_FOOD), keys(DC_FEED_OTR)))
        Nests_BSAT_Markets_1       = sort!(DataFrame([(k[1], k[2], v) for (k, v)  in Nests_BSAT_Markets_0],    [:region, :commodity, :value]))
        Nests_BSAT_Markets_1.nest  = map(x -> x == "Beef"    || x == "Poultry" || x == "Pork" ? "Livestock"   :
                                              x == "SoyMeal" || x == "SoyOil"                 ? "Secondary"   : 
                                              x == "Cotton"                                   ? "Other"       :  
                                              x == "Wheat"                                    ? "Brd_Cereals" :  
                                              x == "Soybean"                                  ? "Soy_Cereals" : 
                                              x == "Rice"                                     ? "Rce_Cereals" :  
                                              x == "Corn"     || x == "Sorghum"               ? "Cereals"     :
                                              x == "Barley"                                   ? "Bly_Cereals" : 
                                              "",   Nests_BSAT_Markets_1.commodity) 
        Nests_BSAT_Markets_1
        Nests_BSAT_Markets_2       = combine(groupby(Nests_BSAT_Markets_1, [:region, :nest]), :value => sum)
        Nests_BSAT_Markets_3       = Dict((row.region, row.nest) => row.value_sum   for  row in eachrow(Nests_BSAT_Markets_2))
        Nests_BSAT_Markets         = Dict(k => (v > 0 ? 1 : missing)  for (k, v)  in Nests_BSAT_Markets_3)

#  --------------------------------------------------------------------------------------------------
      
    #2) Revision of constraints

    local   make_target_df, df0, df, all_columns_USDA_0, all_columns_USDA, all_columns_BSAT, df_LC_BSAT_Market, df_CUR_SUPL_BSAT_Market, 
            df_CUR_SUPL_DOM_BSAT_Market,df_BsStcks_BSAT_Market, df_Q_BSAT_Market, df_IM_BSAT_Market, df_IM_FOOD_BSAT_Market, df_IM_FEED_BSAT_Market, 
            df_IM_FEED_LIV_BSAT_Market, df_IM_FEED_OTR_BSAT_Market, df_IM_OTHR_BSAT_Market, df_IM_CRSH_BSAT_Market, df_DC_BSAT_Market, df_DC_FOOD_BSAT_Market, 
            df_DC_FOOD_BSAT_Market_BUY_LOC,df_DC_FEED_BSAT_Market, df_DC_FEED_LIV_BSAT_Market, df_DC_FEED_OTR_BSAT_Market, df_DC_FEED_OTR_BSAT_Market_BUY_LOC, 
            df_CRSH_BSAT, df_EX_BSAT_Market,df_EndStcks_BSAT_Market, df_Loss_BSAT_Market, df_Z_LIV_Feed_BSAT, df_Constraints_BSAT, df_long_constraints, 
            df_wide_constraints, df_Area_BSAT_Markets, df_Nests_BSAT_Markets_0, df_Nests_BSAT_Markets, df_IM_FEED_LIV_comm_BSAT_Market, df_Feed_BSAT_Feed_DA_Liv, 
            df_Feed_BSAT_Feed_DA_Liv_BUY_LOC, df_Constraints_BSAT_rxk_0, df_Constraints_BSAT_rxk


    #) Constraints: region x commodity level
              
        #) All constraints (defined above as a dictionary) are defined Dataframe with region in rows, products in columns.  
            all_columns_USDA_0         = sort!(DataFrame([(k[1], k[2], v) for (k, v) in LC_BSAT_Market], [:region, :commodity, :value]))
            all_columns_USDA           = unstack(all_columns_USDA_0, :region, :commodity, :value)
            all_columns_USDA.Attribute = fill(string("local_Mkt"), nrow(all_columns_USDA))
            all_columns_BSAT= names(all_columns_USDA)

            function make_target_df(dict::Dict, value_name::Symbol)
                df0 = sort!(DataFrame([(k[1], k[2], v) for (k, v) in dict], [:region, :commodity, value_name]))
                df  = unstack(df0, :region, :commodity, value_name)
                df.Attribute = fill(string(value_name), nrow(df))

                for col in all_columns_BSAT
                    if !(col in names(df))  
                        df[!, col] .= missing  
                    end
                end

                return df
            end

            df_LC_BSAT_Market           = make_target_df(LC_BSAT_Market,             :LC_BSAT_Market)
            df_CUR_SUPL_BSAT_Market     = make_target_df(CUR_SUPL_BSAT_Market,       :CUR_SUPL_BSAT_Market)
            df_CUR_SUPL_DOM_BSAT_Market = make_target_df(CUR_SUPL_DOM_BSAT_Market,   :CUR_SUPL_DOM_BSAT_Market)
            df_BsStcks_BSAT_Market      = make_target_df(BsStcks_BSAT_Market,        :BsStcks_BSAT_Market)
            df_Q_BSAT_Market            = make_target_df(Q_BSAT_Market,              :Q_BSAT_Market)
            df_IM_BSAT_Market           = make_target_df(IM_BSAT_Market,             :IM_BSAT_Market)
            df_IM_FOOD_BSAT_Market      = make_target_df(IM_FOOD_BSAT_Market,        :IM_FOOD_BSAT_Market)
            df_IM_FEED_BSAT_Market      = make_target_df(IM_FEED_BSAT_Market,        :IM_FEED_BSAT_Market)
            df_IM_FEED_LIV_BSAT_Market  = make_target_df(IM_FEED_LIV_BSAT_Market,    :IM_FEED_LIV_BSAT_Market)
            df_IM_FEED_OTR_BSAT_Market  = make_target_df(IM_FEED_OTR_BSAT_Market,    :IM_FEED_OTR_BSAT_Market)
            df_IM_OTHR_BSAT_Market      = make_target_df(IM_OTHR_BSAT_Market,        :IM_OTHR_BSAT_Market)
            df_IM_CRSH_BSAT_Market      = make_target_df(IM_CRSH_BSAT_Market,        :IM_CRSH_BSAT_Market)
            df_DC_BSAT_Market           = make_target_df(DC_BSAT_Market,             :DC_BSAT_Market)
            df_DC_FOOD_BSAT_Market      = make_target_df(DC_FOOD_BSAT_Market,        :DC_FOOD_BSAT_Market)
            df_DC_FOOD_BSAT_Market_BUY_LOC  =make_target_df(DC_FOOD_BSAT_Market_BUY_LOC,        :DC_FOOD_BSAT_Market_BUY_LOC)
            df_DC_FEED_BSAT_Market      = make_target_df(DC_FEED_BSAT_Market,        :DC_FEED_BSAT_Market)
            df_DC_FEED_LIV_BSAT_Market  = make_target_df(DC_FEED_LIV_BSAT_Market,    :DC_FEED_LIV_BSAT_Market)
            df_DC_FEED_OTR_BSAT_Market  = make_target_df(DC_FEED_OTR_BSAT_Market,    :DC_FEED_OTR_BSAT_Market)
            df_DC_FEED_OTR_BSAT_Market_BUY_LOC  =make_target_df(DC_FEED_OTR_BSAT_Market_BUY_LOC,        :DC_FEED_OTR_BSAT_Market_BUY_LOC)
            df_CRSH_BSAT                = make_target_df(CRSH_BSAT,                  :CRSH_BSAT)
            df_EX_BSAT_Market           = make_target_df(EX_BSAT_Market,             :EX_BSAT_Market)
            df_EndStcks_BSAT_Market     = make_target_df(EndStcks_BSAT_Market,       :EndStcks_BSAT_Market)
            df_Loss_BSAT_Market         = make_target_df(Loss_BSAT_Market,           :Loss_BSAT_Market)
            df_Z_LIV_Feed_BSAT          = make_target_df(Z_LIV_Feed_BSAT,            :Z_LIV_Feed_BSAT)

            df_Constraints_BSAT = vcat(df_LC_BSAT_Market, df_CUR_SUPL_BSAT_Market, df_CUR_SUPL_DOM_BSAT_Market, df_BsStcks_BSAT_Market, df_Q_BSAT_Market, 
                                    df_IM_BSAT_Market, df_IM_FOOD_BSAT_Market, df_IM_FEED_BSAT_Market, df_IM_FEED_LIV_BSAT_Market, df_IM_FEED_OTR_BSAT_Market, 
                                    df_IM_OTHR_BSAT_Market, df_IM_CRSH_BSAT_Market, df_DC_BSAT_Market, df_DC_FOOD_BSAT_Market, df_DC_FOOD_BSAT_Market_BUY_LOC,
                                    df_DC_FEED_BSAT_Market, df_DC_FEED_LIV_BSAT_Market, df_DC_FEED_OTR_BSAT_Market, df_DC_FEED_OTR_BSAT_Market_BUY_LOC, df_CRSH_BSAT, 
                                    df_EX_BSAT_Market, df_EndStcks_BSAT_Market, df_Loss_BSAT_Market, df_Z_LIV_Feed_BSAT)

            df_Constraints_BSAT .= coalesce.(df_Constraints_BSAT, 0)
            sort!(df_Constraints_BSAT, [:Attribute, :region])


        #) Preparation of constraints dataframe
            df_long_constraints = stack(df_Constraints_BSAT,
                [:Barley, :Beef, :Corn, :Cotton, :Pork, :Poultry, :Rice, :Sorghum, :SoyMeal, :SoyOil, :Soybean, :Wheat],           
                [:region, :Attribute];                  
                variable_name = :commodity,      
                value_name = :v_         
            )

            df_wide_constraints = unstack(df_long_constraints,
                [:region, :commodity],     
                :Attribute,         
                :v_         
            )
            df_wide_constraints .= coalesce.(df_wide_constraints, 0)
            sort!(df_wide_constraints, [:commodity, :region])        


    #) Constraints: region level
        df_Area_BSAT_Markets = sort!(DataFrame([(k, v) for (k, v) in Area_BSAT_Markets], [:region, :value]))        


    #) Constraints: region x nest level
        df_Nests_BSAT_Markets_0 = sort!(DataFrame([(k[1], k[2], v) for (k, v) in Nests_BSAT_Markets], [:region, :nest, :value]))
        df_Nests_BSAT_Markets   = unstack(df_Nests_BSAT_Markets_0, [:region], :nest, :value)     


    #) Constraints: region x livestock commodity x input
        df_IM_FEED_LIV_comm_BSAT_Market = sort!(DataFrame([(k[1], k[2], k[3], v) for (k, v) in IM_FEED_LIV_comm_BSAT_Market] , [:region, :commodity, :input, :value]))
            rename!(df_IM_FEED_LIV_comm_BSAT_Market, :value => :IM_FEED_LIV_comm_BSAT_Market)

        df_Feed_BSAT_Feed_DA_Liv        = sort!(DataFrame([(k[1], k[2], k[3], v) for (k, v) in Feed_BSAT_Feed_DA_Liv]        , [:region, :commodity, :input, :value]))
            rename!(df_Feed_BSAT_Feed_DA_Liv, :value => :Feed_BSAT_Feed_DA_Liv)

        df_Feed_BSAT_Feed_DA_Liv_BUY_LOC= sort!(DataFrame([(k[1], k[2], k[3], v) for (k, v) in Feed_BSAT_Feed_DA_Liv_BUY_LOC], [:region, :commodity, :input, :value]))
            rename!(df_Feed_BSAT_Feed_DA_Liv_BUY_LOC, :value => :Feed_BSAT_Feed_DA_Liv_BUY_LOC)

        df_Constraints_BSAT_rxk_0 = outerjoin(df_Feed_BSAT_Feed_DA_Liv, df_Feed_BSAT_Feed_DA_Liv_BUY_LOC  , on = [:region, :commodity, :input]) 
        df_Constraints_BSAT_rxk   = outerjoin(df_Constraints_BSAT_rxk_0, df_IM_FEED_LIV_comm_BSAT_Market  , on = [:region, :commodity, :input]) 
                                

#  --------------------------------------------------------------------------------------------------
# PART H: MODEL DISTRIBUTION PARAMETERS
#  --------------------------------------------------------------------------------------------------

    #NOTE: The model is solved in hat calculus in the calibrated share form of Rutherford (1995). Accordingly, all distribution parameters 
    #      correspond to value shares and are calibrated from observed data.

    local phi_i_0, phi_i, phi_f_0, phi_f, PW0_1, tau_x0_1, tau_m0_1, NTM_exp0_1, NTM_imp0_1, inv_liv_0_1, slt_liv_0_1, DC_FEED_LIV_BSAT_Market_df, 
          IM_FEED_LIV_BSAT_Market_df, Nests_BSAT_Markets_df, Q_BSAT_Market_df, CRSH_BSAT_df, IM_CRSH_BSAT_Market_df0, IM_CRSH_BSAT_Market_df, 
          master_data_rk, var_names_MD_rk, col_data_rk, mrk, master_data_rxk, master_data_rxk_i, var_names_MD_rxk, col_data_rxk, mrxk, NDF_Dst_Prm, 
          phi_dFOOD_IMP, phi_dFEED_IMP, phi_VT_FOOD, phi_s_CRH, phi_s_FDD, phi_s_EXP, phi_c_IMP, phi_z_IMP, phi_f_INP, phi_w_INP, phi_w_FDD, phi_DFEED, 
          phi_DFOOD, phi_DCRSH, phi_MFOOD, phi_MCRSH, phi_MOTHR, phi_MFEED, phi_MFEED_LIV, phi_MFEED_LIV_COMM, phi_LND, phi_MKt_EX, phi_MKt_IM, phi_OS_BS, 
          phi_OS_QPrd, phi_OS_M, phi_OD_Tot_DC, phi_OD_EX, phi_OD_ES, phi_OD_ES, phi_n, mrn, phi_u, mrx, phi_l_FDD, mrk_sc, phi_mkt_lc_sec, phi_mkt_im_sec,
          mrk_soy, phi_LOC_sec, phi_IMP_sec, DP_rk, var_names_DP_rk, DP_r, DP_nrk, DP_nr   
    

    #1) Distribution parameters calibrated outside the model 

    #) phi_i(k)   Distribution parameter of value added of commodity k in total production
        phi_i_0 = sort!(info_exogenous[info_exogenous.attribute .== "phi_i", :])
        phi_i   = Dict(phi_i_0.commodity .=> phi_i_0.value) 

    #) phi_f(r,k)  Distibution parameter of LAND within value added of primary commodity k in region r
        phi_f_0  = sort!(info_exogenous[(info_exogenous.attribute .== "phi_f") .& (info_exogenous.year .== string(i)), :])    
        phi_f    = Dict((row.region, row.commodity) => row.value  for row in eachrow(phi_f_0))  


#  --------------------------------------------------------------------------------------------------

    #2) Calculation of distribution parameters

    #2.a) Data preparation
        PW0_1       = PW0_0[:,     [:nest,   :commodity, :value]]
        tau_x0_1    = tau_x0_0[:,  [:region, :commodity, :value]]
        tau_m0_1    = tau_m0_0[:,  [:region, :commodity, :value]]
        NTM_exp0_1  = NTM_exp0_0[:,[:region, :commodity, :value]]
        NTM_imp0_1  = NTM_imp0_0[:,[:region, :commodity, :value]]
        inv_liv_0_1 = inv_liv_0[: ,[:region, :commodity, :value]]
        slt_liv_0_1 = slt_liv_0[: ,[:region, :commodity, :value]]
        DC_FEED_LIV_BSAT_Market_df = sort!(DataFrame([(k[1], k[2], v) for (k, v) in DC_FEED_LIV_BSAT_Market]        , [:region, :commodity, :value]))
        IM_FEED_LIV_BSAT_Market_df = sort!(DataFrame([(k[1], k[2], v) for (k, v) in IM_FEED_LIV_BSAT_Market]        , [:region, :commodity, :value])) 
        Nests_BSAT_Markets_df      = sort!(DataFrame([(k[1], k[2], v) for (k, v) in Nests_BSAT_Markets]             , [:region, :nest, :value]))
        Q_BSAT_Market_df           = sort!(DataFrame([(k[1], k[2], v) for (k, v) in Q_BSAT_Market]                  , [:region, :commodity, :value]))
        CRSH_BSAT_df               = sort!(DataFrame([(k[1], k[2], v) for (k, v) in CRSH_BSAT]                      , [:region, :commodity, :value]))
        IM_CRSH_BSAT_Market_df0    = sort!(DataFrame([(k[1], k[2], v) for (k, v) in IM_CRSH_BSAT_Market]            , [:region, :commodity, :value]))
        IM_CRSH_BSAT_Market_df     = sort!(IM_CRSH_BSAT_Market_df0[IM_CRSH_BSAT_Market_df0.commodity .== "Soybean", :])


    #2.b) Master Data - rk level
        master_data_rk = deepcopy(PW0_1)
            rename!(master_data_rk,   :value => :PWorld)

        master_data_rk = outerjoin(master_data_rk, tau_x0_1             , on = :commodity)
            rename!(master_data_rk,   :value => :tar_X) 

        master_data_rk = outerjoin(master_data_rk, tau_m0_1             , on = [:commodity, :region])
            rename!(master_data_rk,   :value => :tar_M) 

        master_data_rk = outerjoin(master_data_rk, NTM_exp0_1           , on = [:commodity, :region])
            rename!(master_data_rk,   :value => :NTM_X)

        master_data_rk = outerjoin(master_data_rk, NTM_imp0_1           , on = [:commodity, :region])
            rename!(master_data_rk,   :value => :NTM_M)

        master_data_rk = outerjoin(master_data_rk, Target_Q_df          , on = [:commodity, :region])    
            rename!(master_data_rk,   :value => :Target_Q)

        master_data_rk = outerjoin(master_data_rk, Target_BS_df         , on = [:commodity, :region])
            rename!(master_data_rk,   :value => :Target_BS)  

        master_data_rk = outerjoin(master_data_rk, Target_M_df          , on = [:commodity, :region])
            rename!(master_data_rk,   :value => :Target_M)

        master_data_rk = outerjoin(master_data_rk, Target_Loss_df       , on = [:commodity, :region])
            rename!(master_data_rk,   :value => :Target_Loss) 

        master_data_rk = outerjoin(master_data_rk, Target_ES_df         , on = [:commodity, :region])
            rename!(master_data_rk,   :value => :Target_ES)

        master_data_rk = outerjoin(master_data_rk, Target_M_FOOD_df     , on = [:commodity, :region])
            rename!(master_data_rk,   :value => :Target_M_FOOD)

        master_data_rk = outerjoin(master_data_rk, Target_M_FEED_LIV_df , on = [:commodity, :region])
            rename!(master_data_rk,   :value => :Target_M_FEED_LIV) 

        master_data_rk = outerjoin(master_data_rk, Target_M_FEED_OTR_df , on = [:commodity, :region])
            rename!(master_data_rk,   :value => :Target_M_FEED_OTR)

        master_data_rk = outerjoin(master_data_rk, Target_M_CRUSH_df    , on = [:commodity, :region])
            rename!(master_data_rk,   :value => :Target_M_Crush) 

        master_data_rk = outerjoin(master_data_rk, Target_M_OTHR_df     , on = [:commodity, :region]) 
            rename!(master_data_rk,   :value => :Target_M_OTHR)

        master_data_rk = outerjoin(master_data_rk, DC_FEED_LIV_df       , on = [:commodity, :region])
            rename!(master_data_rk,   :value => :DC_FEED_LIV) 

        master_data_rk = outerjoin(master_data_rk, DC_FEED_OTR_df       , on = [:commodity, :region])
            rename!(master_data_rk,   :value => :DC_FEED_OTR) 

        master_data_rk = outerjoin(master_data_rk, Target_DC_FOOD_df    , on = [:commodity, :region])
            rename!(master_data_rk,   :value => :Target_DC_FOOD) 

        master_data_rk = outerjoin(master_data_rk, Target_Crsh_df       , on = [:commodity, :region])
            rename!(master_data_rk,   :value => :Target_Crush)

        master_data_rk = outerjoin(master_data_rk, Target_X_df          , on = [:commodity, :region])
            rename!(master_data_rk,   :value => :Target_X)  

        master_data_rk = outerjoin(master_data_rk, Target_A_df          , on = [:commodity, :region])
            rename!(master_data_rk,   :value => :Target_A)  

        master_data_rk = outerjoin(master_data_rk, df_wide_constraints    , on = [:commodity, :region])

        master_data_rk = outerjoin(master_data_rk, Nests_BSAT_Markets_df  , on = [:nest, :region])
            rename!(master_data_rk,   :value => :Nests_BSAT_Markets) 

        #NOTE 1.: Julia does not treat a missing value as Excel, which treats it as a zero. This is problematic, because any operation with a "missing value" 
        #         results in a "missing value" (e.g. 1 + missing = missing. In contrast, Excel yields 1 in similar calculation as a result). Due to this, all 
        #         missing values are changed to zeros in the master_rk database.
            var_names_MD_rk = names(master_data_rk)
            filter!(x -> !(x in ["nest", "commodity", "region"]), var_names_MD_rk)
                for col in var_names_MD_rk
                    master_data_rk[!, col] = coalesce.(master_data_rk[!, col], 0)
                end
            master_data_rk
        
        #NOTE 2.: For numerical precision, all variables are converted to BigFloat
            for col in names(master_data_rk)
                col_data_rk = master_data_rk[!, col]
                if eltype(col_data_rk) <: Union{Missing, Float64}
                    master_data_rk[!, col] = map(x -> ismissing(x) ? missing : BigFloat(x), col_data_rk)
                elseif eltype(col_data_rk) <: Float64
                    master_data_rk[!, col] = BigFloat.(col_data_rk)
                end
            end
            master_data_rk
        
        #NOTE 3.: A copy of this dataframe is created with a shorter name to facilitate the coding below.  
            mrk = deepcopy(master_data_rk)


    #2.c) Master Data - rxk level
    #NOTE: In this database, commodities correspond to livestock commodities, while inputs represent all commodities used in their production.
  
        #) inputs data
        master_data_rxk_i = deepcopy(PW0_1)
            rename!(master_data_rxk_i,   :value => :PWorld_input)

        master_data_rxk_i = outerjoin(master_data_rxk_i, tau_m0_1                   , on = [:commodity])
            rename!(master_data_rxk_i,   :value => :tar_M_input)

        master_data_rxk_i = outerjoin(master_data_rxk_i, NTM_imp0_1                 , on = [:commodity, :region])
            rename!(master_data_rxk_i,   :value => :NTM_M_input)

        master_data_rxk_i = outerjoin(master_data_rxk_i, DC_FEED_LIV_BSAT_Market_df , on = [:commodity, :region])
            rename!(master_data_rxk_i,   :value => :DC_FEED_LIV_BSAT_Market)

        master_data_rxk_i = outerjoin(master_data_rxk_i, IM_FEED_LIV_BSAT_Market_df , on = [:commodity, :region])
            rename!(master_data_rxk_i,   :value => :IM_FEED_LIV_BSAT_Market)

        rename!(master_data_rxk_i,       :commodity => :input)


        #) overall data  
        #NOTE: Unlike "master_data_rk", defined above—where all region × commodity combinations are automatically generated when
        #      "PWorld" and "tar_X" are merged—these combinations must be explicitly created in "master_data_rxk". In this case,
        #      no merge step generates them automatically.The command "leftjoin" is also sused to avoid introducing unnecessary 
        #      observations when merging data at the commodity, region, and input level. For example, the reference price is only
        #      required for beef, pork, and poultry. Using a left join prevents this price information from being added to other 
        #      products, thereby keeping the resulting DataFrame consistent.

        master_data_rxk = DataFrame(Iterators.product(region, liv_goods, inp_liv),            [:region, :commodity, :input])

        master_data_rxk = leftjoin(master_data_rxk, master_data_rxk_i                  , on = [:region,             :input])

        master_data_rxk = leftjoin(master_data_rxk, Feed_DA_Liv_df                     , on = [:region, :commodity, :input])
            rename!(master_data_rxk,   :value => :Feed_DA_Liv)

        master_data_rxk = leftjoin(master_data_rxk, select(PW0_1, :commodity, :value)  , on = [:commodity])
            rename!(master_data_rxk,   :value => :PWorld_comm)

        master_data_rxk = leftjoin(master_data_rxk,           Target_M_FEED_LIV_comm_df, on = [:region, :commodity, :input])
            rename!(master_data_rxk,   :value => :Target_M_FEED_LIV_comm)

        master_data_rxk = leftjoin(master_data_rxk, Target_Q_df                        , on = [:region, :commodity])    
            rename!(master_data_rxk,   :value => :Target_Q)

        master_data_rxk = leftjoin(master_data_rxk, inv_liv_0_1                        , on = [:region, :commodity])    
            rename!(master_data_rxk,   :value => :inv_liv)

        master_data_rxk = leftjoin(master_data_rxk, slt_liv_0_1                        , on = [:region, :commodity])    
            rename!(master_data_rxk,   :value => :slt_liv)

        master_data_rxk = leftjoin(master_data_rxk, Q_BSAT_Market_df                   , on = [:region, :commodity])    
            rename!(master_data_rxk,   :value => :Q_BSAT_Market)

        master_data_rxk = leftjoin(master_data_rxk,           df_Constraints_BSAT_rxk  , on = [:region, :commodity, :input])

        #NOTE 1.: As above, all missing values are changed to zero.
            var_names_MD_rxk = names(master_data_rxk)
            filter!(x -> !(x in ["nest", "commodity", "region", "input"]), var_names_MD_rxk)
                for col in var_names_MD_rxk
                    master_data_rxk[!, col] = coalesce.(master_data_rxk[!, col], 0)
                end
            master_data_rxk

        #NOTE 2.: For numerical precision, all variables are converted to BigFloat.
            for col in names(master_data_rxk)
                col_data_rxk = master_data_rxk[!, col]
                if eltype(col_data_rxk) <: Union{Missing, Float64}
                    master_data_rxk[!, col] = map(x -> ismissing(x) ? missing : BigFloat(x), col_data_rxk)
                elseif eltype(col_data_rxk) <: Float64
                    master_data_rxk[!, col] = BigFloat.(col_data_rxk)
                end
            end
            master_data_rxk

        #NOTE: A copy of this dataframe is created with a shorter name to facilitate the coding below.             
            mrxk = deepcopy(master_data_rxk)


    #2.d) key variables

        #) Vle_TOT_SA(r,k)        Value of Total SUPPLY of commodity k in region r
            mrk.Vle_TOT_SA      = (((mrk.Target_BS .+ mrk.Target_Q) .* mrk.PWorld) .+ (mrk.Target_M .* mrk.PWorld .* (1 .+ mrk.NTM_M) .* (1 .+ mrk.tar_M))) .- (mrk.PWorld .* mrk.Target_Loss)

        #) Vle_CUR_SA(r,k)       Value of Current SUPPLY of commodity k in region r
            mrk.Vle_CUR_SA      = mrk.Vle_TOT_SA .- (mrk.Target_ES .*  mrk.PWorld) 
               
        #) Vle_TOT_BS(r,k)       Value of Total Beginning Stocks of commodity k in region r
            mrk.Vle_TOT_BS      = mrk.PWorld .* mrk.Target_BS

        #) Vle_TOT_Q(r,k)         Value of Total Production of commodity k in region r
            mrk.Vle_TOT_Q       = mrk.PWorld .* mrk.Target_Q

        #) Vle_TOT_M(r,k)         Value of Total Imports of commodity k in region r
            mrk.Vle_TOT_M       = mrk.Target_M      .* mrk.PWorld .* (1 .+ mrk.NTM_M) .* (1 .+ mrk.tar_M)

        #) Vle_M_FOOD(r,k)        Value of FOOD Imports of commodity k in region r
            mrk.Vle_M_FOOD      = mrk.Target_M_FOOD .* mrk.PWorld .* (1 .+ mrk.NTM_M) .* (1 .+ mrk.tar_M)

        #) Vle_M_FEED(r,k)        Value of FEED Imports of commodity k in region r
            mrk.Vle_M_FEED      = (mrk.Target_M_FEED_LIV .+ mrk.Target_M_FEED_OTR)  .* mrk.PWorld .* (1 .+ mrk.NTM_M) .* (1 .+ mrk.tar_M)

        #) Vle_M_FEED_LIV(r,k)    Value of FEED Imports of commodity k used for feeding USDA livestock commodities in region r
            mrk.Vle_M_FEED_LIV  = mrk.Target_M_FEED_LIV .* mrk.PWorld .* (1 .+ mrk.NTM_M) .* (1 .+ mrk.tar_M)

        #) Vle_M_FEED_OTR(r,k)    Value of FEED Imports of commodity k used for feeding Other livestock commodities in region r
            mrk.Vle_M_FEED_OTR  = mrk.Target_M_FEED_OTR .* mrk.PWorld .* (1 .+ mrk.NTM_M) .* (1 .+ mrk.tar_M)
 
        #) Vle_M_Crush(r,k)       Value of Imported Soybeans for crushing in region r
            mrk.Vle_M_Crush     = mrk.Target_M_Crush    .* mrk.PWorld .* (1 .+ mrk.NTM_M) .* (1 .+ mrk.tar_M)

        #) Vle_M_Othr(r,k)        Value of total Imports for other uses of commodity k in region r        
            mrk.Vle_M_Othr      = mrk.Target_M_OTHR     .* mrk.PWorld .* (1 .+ mrk.NTM_M) .* (1 .+ mrk.tar_M)

        #) Vle_TOT_DC_FEED(r,k)   Value of Total FEED Consumption of commodity k in region r
            mrk.Vle_TOT_DC_FEED = ((mrk.Target_M_FEED_LIV .+ mrk.Target_M_FEED_OTR) .* mrk.PWorld .* (1 .+ mrk.NTM_M) .* (1 .+ mrk.tar_M)) .+ (((mrk.DC_FEED_LIV  .+ mrk.DC_FEED_OTR) .- (mrk.Target_M_FEED_LIV .+ mrk.Target_M_FEED_OTR)).*mrk.PWorld)

        #) Vle_TOT_DC_FOOD(r,k)   Value of Total FOOD Consumption of commodity k in region r
            mrk.Vle_TOT_DC_FOOD = (mrk.Target_M_FOOD    .* mrk.PWorld .* (1 .+ mrk.NTM_M) .* (1 .+ mrk.tar_M)) .+ ((mrk.Target_DC_FOOD .- mrk.Target_M_FOOD).* mrk.PWorld)

        #) Vle_TOT_DC_CRSH(r,k)   Value of Total CRUSHING Consumption of commodity k in region r
            mrk.Vle_TOT_DC_CRSh = (mrk.Target_M_Crush   .* mrk.PWorld .* (1 .+ mrk.NTM_M) .* (1 .+ mrk.tar_M))  .+ ((mrk.Target_Crush  .-mrk.Target_M_Crush).* mrk.PWorld)

        #) Vle_TOT_DC(r,k)        Value of Total Consumption of commodity k in every region r
            mrk.Vle_TOT_DC      = mrk.Vle_TOT_DC_FOOD .+ mrk.Vle_TOT_DC_FEED .+ mrk.Vle_TOT_DC_CRSh

        #) Vle_TOT_DA_FOOD(r,k)   Value of Total FOOD DEMAND of commodity k in region r
            mrk.Vle_TOT_DA_FOOD = (mrk.Target_M_FOOD    .* mrk.PWorld .* (1 .+ mrk.NTM_M) .* (1 .+ mrk.tar_M)) .+ ((mrk.Target_DC_FOOD .- mrk.Target_M_FOOD).* mrk.PWorld)

        #) Vle_TOT_DC_FEED_OTR(r,k)   Value of Total FEED Consumption of commodity k used for feeding Other livestock commodities in region r
            mrk.Vle_TOT_DC_FEED_OTR = (mrk.Target_M_FEED_OTR .* mrk.PWorld .* (1 .+ mrk.NTM_M) .* (1 .+ mrk.tar_M)) .+ ((mrk.DC_FEED_OTR .- mrk.Target_M_FEED_OTR).*mrk.PWorld)

        #) Vle_TOT_DA_FOOD_FEED_NST(n,r,k) Value of Total FOOD & FEED DEMAND (for OTHER) of commodity k within nest n in region r
            mrk.Vle_TOT_DA_FOOD_FEED_NST = mrk.Vle_TOT_DA_FOOD .+ mrk.Vle_TOT_DC_FEED_OTR

        #) Vle_TOT_X(r,k)         Value of Total Exports of commodity k in region r
            mrk.Vle_TOT_X       = mrk.Target_X .* mrk.PWorld .* (1 .- mrk.NTM_X) .* (1 .- mrk.tar_X)

        #) Vle_TOT_ES(r,k)        Value of Total Ending Stocks of commodity k in region r
            mrk.Vle_TOT_ES      = mrk.PWorld .* mrk.Target_ES

        #) Vle_Demand(r,k)        Value of Overall Demand of commodity k in region r
            mrk.Vle_Demand      = mrk.Vle_TOT_DC .+ mrk.Vle_TOT_X .+ mrk.Vle_TOT_ES  

        #) Vle_Supply(r,k)        Value of Overall Supply of commodity k in in region r
            mrk.Vle_Supply      = mrk.Vle_TOT_BS .+ mrk.Vle_TOT_Q .+ mrk.Vle_TOT_M 
        #NOTE: Since the loss is a fixed share of the overall supply XS, it must be excluded from the calculation.

        #) Vle_Feed_DA_Liv0(r,x,k)           Value of Demand of input k for feeding livestock commodity x in region r
            mrxk.Vle_Feed_DA_Liv0           = (mrxk.Target_M_FEED_LIV_comm .* mrxk.PWorld_input .* (1 .+ mrxk.NTM_M_input) .* (1 .+ mrxk.tar_M_input)) .+ (mrxk.Feed_DA_Liv .- mrxk.Target_M_FEED_LIV_comm) .* mrxk.PWorld_input

        #) Vle_Target_M_FEED_LIV_comm(r,x,k) Value of Imports of input k for feeding livestock commosity k in region r
            mrxk.Vle_Target_M_FEED_LIV_comm = (mrxk.Target_M_FEED_LIV_comm .* mrxk.PWorld_input .* (1 .+ mrxk.NTM_M_input) .* (1 .+ mrxk.tar_M_input))

        #) Vle_TOT_Q(r,k)                    Value of Total Production of commodity k in region r
            mrxk.Vle_TOT_Q                  = mrxk.PWorld_comm .* mrxk.Target_Q


    #2.e) Calculation of Distribution Parameters

        #NOTE: the following function addresses cases where a ratio in the calculation of these parameter returns a missing or NaN value. 
        #      In all such cases, the result is set to zero.
        
            function NDF_Dst_Prm(x)
                if x === missing || isnan(x)
                    return 0
                else
                    return x
                end
            end


        #) phi_dFOOD_IMP(r,k)     Share of FOOD imports in total FOOD demand of commodity k in region r
            mrk.phi_dFOOD_IMP   = (NDF_Dst_Prm.(mrk.Vle_M_FOOD ./ mrk.Vle_TOT_DA_FOOD)) .* coalesce.(mrk.DC_FOOD_BSAT_Market, 0) 
                phi_dFOOD_IMP   = Dict((row.region, row.commodity) =>  BigFloat(row.phi_dFOOD_IMP) for row in eachrow(mrk))

        #) phi_dFEED_IMP(r,k)     Share of FEED imports in total FEED demand of commodity k for feeding other livestock in region r
            mrk.phi_dFEED_IMP   = (NDF_Dst_Prm.(mrk.Vle_M_FEED_OTR ./ mrk.Vle_TOT_DC_FEED_OTR)) .* coalesce.(mrk.DC_FEED_OTR_BSAT_Market, 0) 
                phi_dFEED_IMP   = Dict((row.region, row.commodity) =>  BigFloat(row.phi_dFEED_IMP) for row in eachrow(mrk))

        #) phi_VT_FOOD(r,k)       Share of FOOD Demand in TOTAL demand of commodity k in region r
            mrk.phi_VT_FOOD     = (NDF_Dst_Prm.(mrk.Vle_TOT_DA_FOOD ./ (mrk.Vle_TOT_DA_FOOD .+ mrk.Vle_TOT_DC_FEED_OTR))) .* max.(coalesce.(mrk.DC_FOOD_BSAT_Market, 0),coalesce.(mrk.DC_FEED_OTR_BSAT_Market, 0))
                phi_VT_FOOD     = Dict((row.region, row.commodity) =>  BigFloat(row.phi_VT_FOOD) for row in eachrow(mrk))

        #) phi_s_CRH(r,k)         Share of Demand of soybeans for crushing in total consumption in region r
            mrk.phi_s_CRH       = (NDF_Dst_Prm.(mrk.Vle_TOT_DC_CRSh ./ mrk.Vle_TOT_DC)) .* (coalesce.(mrk.CUR_SUPL_DOM_BSAT_Market, 0))
                phi_s_CRH       = Dict((row.region, row.commodity) =>  BigFloat(row.phi_s_CRH) for row in eachrow(mrk))

        #) phi_s_FDD              Share of FEED consumption in total consumption of commodity k region r
            mrk.phi_s_FDD       = (NDF_Dst_Prm.(mrk.Vle_TOT_DC_FEED ./ mrk.Vle_TOT_DC)) .* (coalesce.(mrk.CUR_SUPL_DOM_BSAT_Market, 0))
                phi_s_FDD       = Dict((row.region, row.commodity) =>  BigFloat(row.phi_s_FDD) for row in eachrow(mrk))

        #) phi_s_EXP(r,k)         Share of exports supply in the current supply of commodity k in region r
            mrk.phi_s_EXP       = (NDF_Dst_Prm.(mrk.Vle_TOT_X ./  mrk.Vle_CUR_SA))        .* (coalesce.(mrk.CUR_SUPL_BSAT_Market, 0))
                phi_s_EXP       = Dict((row.region, row.commodity) => BigFloat(row.phi_s_EXP) for row in eachrow(mrk))

        #) phi_c_IMP(r,k)         Share of soybean IMPORTS for crushing in total demand for crushing in region r
            mrk.phi_c_IMP       = (NDF_Dst_Prm.(mrk.Vle_M_Crush ./ mrk.Vle_TOT_DC_CRSh)) .* (coalesce.(mrk.CRSH_BSAT, 0)) 
                phi_c_IMP       = Dict((row.region, row.commodity) => BigFloat(row.phi_c_IMP) for row in eachrow(mrk))

        #) phi_z_IMP(r,k,g)       Share of IMPORTS of commodity g as input for feeding livestock commodity k in region r
            mrxk.phi_z_IMP      = (NDF_Dst_Prm.(mrxk.Vle_Target_M_FEED_LIV_comm ./ mrxk.Vle_Feed_DA_Liv0)) .*(coalesce.(mrxk.Feed_BSAT_Feed_DA_Liv, 0))
                 phi_z_IMP      = Dict((row.region, row.commodity, row.input) => BigFloat(row.phi_z_IMP) for row in eachrow(mrxk))

        #) phi_f_INP(r,k,g)       Share of total demand of commodity g to produce livestock commodity k in region r
            transform!(groupby(mrxk, [:region, :commodity]), :Vle_Feed_DA_Liv0 => sum => :tot_Vle_Feed_DA_Liv0)
            mrxk.phi_f_INP      = (NDF_Dst_Prm.(mrxk.Vle_Feed_DA_Liv0 ./ mrxk.tot_Vle_Feed_DA_Liv0))       .*(coalesce.(mrxk.Feed_BSAT_Feed_DA_Liv, 0))
                 phi_f_INP      = Dict((row.region, row.commodity, row.input) => BigFloat(row.phi_f_INP) for row in eachrow(mrxk))

        #) phi_w_INP(r,g,k)       Share of total demand of livestock commodity g in the total demand of commodity k for feeding in region r
            transform!(groupby(mrxk, [:region, :input]),     :Vle_Feed_DA_Liv0 => sum => :tot_Vle_Feed_DA_Liv0_inp)
            mrxk.phi_w_INP      = (NDF_Dst_Prm.(mrxk.Vle_Feed_DA_Liv0 ./ mrxk.tot_Vle_Feed_DA_Liv0_inp))   .*(coalesce.(mrxk.DC_FEED_LIV_BSAT_Market, 0))
                 phi_w_INP      = Dict((row.region, row.commodity, row.input) => BigFloat(row.phi_w_INP) for row in eachrow(mrxk))
 
        #) phi_w_FDD(r,k)         Share of feed demand for commodity k used by other livestock in total feed demand in region r
            mrk.phi_w_FDD       = (NDF_Dst_Prm.(mrk.Vle_TOT_DC_FEED_OTR ./ mrk.Vle_TOT_DC_FEED))   .*(coalesce.(mrk.DC_FEED_BSAT_Market, 0))
                phi_w_FDD       = Dict((row.region, row.commodity) => BigFloat(row.phi_w_FDD) for row in eachrow(mrk))

        #) phi_DFEED(r,k)         Share of FEED Consumption in total Consumption of commodity k in region r
            mrk.phi_DFEED       = NDF_Dst_Prm.(mrk.Vle_TOT_DC_FEED ./ mrk.Vle_TOT_DC)  .* (coalesce.(mrk.DC_BSAT_Market, 0))  
                phi_DFEED       = Dict((row.region, row.commodity) => BigFloat(row.phi_DFEED) for row in eachrow(mrk))

        #) phi_DFOOD(r,k)         Share of FOOD Consumption in total Consumption of commodity k in region r
            mrk.phi_DFOOD       = NDF_Dst_Prm.(mrk.Vle_TOT_DC_FOOD ./ mrk.Vle_TOT_DC) .* (coalesce.(mrk.DC_BSAT_Market, 0)) 
                phi_DFOOD       = Dict((row.region, row.commodity) => BigFloat(row.phi_DFOOD) for row in eachrow(mrk))

        #) phi_DCRSH(r,k)         Share of CRUSH Consumption in total Consumption of commodity k in region r 
            mrk.phi_DCRSH       = NDF_Dst_Prm.(mrk.Vle_TOT_DC_CRSh ./ mrk.Vle_TOT_DC) .* (coalesce.(mrk.DC_BSAT_Market, 0)) 
                phi_DCRSH       = Dict((row.region, row.commodity) => BigFloat(row.phi_DCRSH) for row in eachrow(mrk))

        #) phi_MFOOD(r,k)         Share of FOOD Imports in total Imports of commodity k in region r
            mrk.phi_MFOOD       = NDF_Dst_Prm.(mrk.Vle_M_FOOD ./ mrk.Vle_TOT_M)       .* (coalesce.(mrk.IM_BSAT_Market, 0))  
                phi_MFOOD       = Dict((row.region, row.commodity) => BigFloat(row.phi_MFOOD) for row in eachrow(mrk))

        #) phi_MCRSH(r,k)         Share of imports of soybeans for crushing in total imports in region r 
            mrk.phi_MCRSH       = NDF_Dst_Prm.(mrk.Vle_M_Crush ./ mrk.Vle_TOT_M)      .* (coalesce.(mrk.IM_BSAT_Market, 0)) 
                phi_MCRSH       = Dict((row.region, row.commodity) => BigFloat(row.phi_MCRSH) for row in eachrow(mrk))

        #) phi_MOTHR(r,k)         Share of imports for other uses in total imports of commodity k in region r
            mrk.phi_MOTHR       = NDF_Dst_Prm.(mrk.Vle_M_Othr ./ mrk.Vle_TOT_M)       .* (coalesce.(mrk.IM_BSAT_Market, 0))
                phi_MOTHR       = Dict((row.region, row.commodity) => BigFloat(row.phi_MOTHR) for row in eachrow(mrk))
   
        #) phi_MFEED(r,k)         Share of FEED imports in total imports of commodity k in region r
            mrk.phi_MFEED       = NDF_Dst_Prm.(mrk.Vle_M_FEED ./ mrk.Vle_TOT_M)       .* (coalesce.(mrk.IM_BSAT_Market, 0)) 
                phi_MFEED       = Dict((row.region, row.commodity) => BigFloat(row.phi_MFEED) for row in eachrow(mrk))
         
        #) phi_MFEED_LIV(r,k)     Share of FEED Imports of commodity k for feeding USDA livestock commodities in total FEED imports in region r
            mrk.phi_MFEED_LIV   = NDF_Dst_Prm.(mrk.Vle_M_FEED_LIV ./ mrk.Vle_M_FEED)  .* (coalesce.(mrk.IM_FEED_BSAT_Market, 0)) 
                phi_MFEED_LIV   = Dict((row.region, row.commodity) => BigFloat(row.phi_MFEED_LIV) for row in eachrow(mrk))

        #) phi_MFEED_LIV_COMM(r,x,k)  Share of FEED Imports of commodity k for feeding USDA livestock commodity x in region r
            transform!(groupby(mrxk, [:region, :input]),     :Vle_Target_M_FEED_LIV_comm => sum => :tot_Vle_Target_M_FEED_LIV_comm_inp)
            mrxk.phi_MFEED_LIV_COMM   = NDF_Dst_Prm.(mrxk.Vle_Target_M_FEED_LIV_comm ./ mrxk.tot_Vle_Target_M_FEED_LIV_comm_inp)  .* (coalesce.(mrxk.IM_FEED_LIV_BSAT_Market, 0)) 
                 phi_MFEED_LIV_COMM   = Dict((row.region, row.commodity, row.input) => BigFloat(row.phi_MFEED_LIV_COMM) for row in eachrow(mrxk))

        #) phi_LND(r,k)           Share of harvested land of commodity k in region r
            transform!(groupby(mrk, [:region]),     :Target_A => sum => :tot_Target_A)
            mrk.phi_LND         = NDF_Dst_Prm.(mrk.Target_A ./ mrk.tot_Target_A)         .* (coalesce.(mrk.Q_BSAT_Market, 0))
                phi_LND         = Dict((row.region, row.commodity) => BigFloat(row.phi_LND) for row in eachrow(mrk))
        
        #) phi_MKt_EX(r,k)        Share of EXPORTS of commodity k from region r in the total exports of k
            transform!(groupby(mrk, [:commodity]),     :Vle_TOT_X => sum => :tot_Vle_TOT_X)
            mrk.phi_MKt_EX      = NDF_Dst_Prm.(mrk.Vle_TOT_X ./ mrk.tot_Vle_TOT_X)         
                phi_MKt_EX      = Dict((row.region, row.commodity) => BigFloat(row.phi_MKt_EX) for row in eachrow(mrk))

        #) phi_MKt_IM(r,k)        Share of IMPORTS of commodity k in region r in the total imports of k
            transform!(groupby(mrk, [:commodity]),     :Vle_TOT_M => sum => :tot_Vle_TOT_M)
            mrk.phi_MKt_IM      = NDF_Dst_Prm.(mrk.Vle_TOT_M ./ mrk.tot_Vle_TOT_M)
                phi_MKt_IM      = Dict((row.region, row.commodity) => BigFloat(row.phi_MKt_IM) for row in eachrow(mrk))

        #) phi_OS_BS(r,k)         Share of Beginning Stocks in Total Supply of commodity k in region r
            mrk.phi_OS_BS       = NDF_Dst_Prm.(mrk.Vle_TOT_BS ./ mrk.Vle_Supply)  .* (coalesce.(mrk.LC_BSAT_Market,0)) 
                phi_OS_BS       = Dict((row.region, row.commodity) => BigFloat(row.phi_OS_BS) for row in eachrow(mrk))

        #) phi_OS_QPrd(r,k)       Share of Production in Total Supply of commodity k in region r   
            mrk.phi_OS_QPrd     = NDF_Dst_Prm.(mrk.Vle_TOT_Q ./ mrk.Vle_Supply)   .* (coalesce.(mrk.LC_BSAT_Market,0))  
                phi_OS_QPrd     = Dict((row.region, row.commodity) => BigFloat(row.phi_OS_QPrd) for row in eachrow(mrk))
    
        #) phi_OS_M(r,k)          Share of total imports in total Supply of commodity k in region r                                                                                                      
            mrk.phi_OS_M        = NDF_Dst_Prm.(mrk.Vle_TOT_M ./ mrk.Vle_Supply)   .* (coalesce.(mrk.LC_BSAT_Market,0))
                phi_OS_M        = Dict((row.region, row.commodity) => BigFloat(row.phi_OS_M) for row in eachrow(mrk))

        #) phi_OD_Tot_DC(r,k)     Share of Total Consumption in total Demand of commodity k in region r
            mrk.phi_OD_Tot_DC   = NDF_Dst_Prm.(mrk.Vle_TOT_DC ./ mrk.Vle_Demand).* (coalesce.(mrk.LC_BSAT_Market,0))  
                phi_OD_Tot_DC   = Dict((row.region, row.commodity) => BigFloat(row.phi_OD_Tot_DC) for row in eachrow(mrk))

        #) phi_OD_EX(r,k)         Share of Exports in total Demand of commodity k in region r
            mrk.phi_OD_EX       = NDF_Dst_Prm.(mrk.Vle_TOT_X  ./ mrk.Vle_Demand) .* (coalesce.(mrk.LC_BSAT_Market,0))
                phi_OD_EX       = Dict((row.region, row.commodity) => BigFloat(row.phi_OD_EX) for row in eachrow(mrk))
    
        #) phi_OD_ES(r,k)         Share of Ending Stocks in total Demand of commodity k in region r
            mrk.phi_OD_ES       = NDF_Dst_Prm.(mrk.Vle_TOT_ES  ./ mrk.Vle_Demand).* (coalesce.(mrk.LC_BSAT_Market,0))
                phi_OD_ES       = Dict((row.region, row.commodity) => BigFloat(row.phi_OD_ES) for row in eachrow(mrk))
       
        #) phi_n(r,n,k)           Share of the total demand of commodity k within nest n in region r
            transform!(groupby(mrk, [:region, :nest]),     :Vle_TOT_DA_FOOD_FEED_NST => sum => :tot_Vle_TOT_DA_FOOD_FEED_NST_rn)
            mrk.phi_n           = NDF_Dst_Prm.(mrk.Vle_TOT_DA_FOOD_FEED_NST ./mrk.tot_Vle_TOT_DA_FOOD_FEED_NST_rn) .* (coalesce.(mrk.Nests_BSAT_Markets,0))
                phi_n           = Dict((row.region, row.nest, row.commodity) => BigFloat(row.phi_n ) for row in eachrow(mrk))          

        #) phi_u(r,n)             Share of the total demand of nest n in region r
            transform!(groupby(mrk, [:region]),             :Vle_TOT_DA_FOOD_FEED_NST => sum => :tot_Vle_TOT_DA_FOOD_FEED_NST_r)
            mrk.phi_u           = NDF_Dst_Prm.(mrk.tot_Vle_TOT_DA_FOOD_FEED_NST_rn ./ mrk.tot_Vle_TOT_DA_FOOD_FEED_NST_r) 
            mrn                 = combine(groupby(mrk, [:region, :nest]), :phi_u       => mean)
                phi_u           = Dict((row.region, row.nest) => BigFloat(row.phi_u_mean ) for row in eachrow(mrn))
            
        #) phi_l_FDD(r,x)         Share of FEED Demand in the production of livestock commodity x in region r
            mrxk.phi_l_FDD      = min.((NDF_Dst_Prm.((mrxk.tot_Vle_Feed_DA_Liv0 .*(mrxk.slt_liv ./ (mrxk.slt_liv .+ mrxk.inv_liv))) ./ mrxk.Vle_TOT_Q) .* (coalesce.(mrxk.Q_BSAT_Market,0))),1) 
            mrx                 = combine(groupby(mrxk, [:region, :commodity]), :phi_l_FDD       => mean)
                phi_l_FDD       = Dict((row.region, row.commodity) => BigFloat(row.phi_l_FDD_mean ) for row in eachrow(mrx))

        #) phi_mkt_lc_sec(r,k)    Share of Secondary commodity k in the total LOCAL market of secondary commodities in region r - value of local production
        #) phi_mkt_im_sec(r,k)    Share of Secondary commodity k in the total IMPORTS market of secondary commodities in region r - value of imports
            mrk_sc              = sort!(mrk[mrk.nest .== "Secondary",  [:region, :commodity, :Vle_TOT_Q, :Q_BSAT_Market]])
            mrk_sc              = leftjoin(mrk_sc, select(CRSH_BSAT_df,[:region, :value])  , on = [:region])
                rename!(mrk_sc,   :value => :CRSH_BSAT)
                mrk_sc.CRSH_BSAT = coalesce.(mrk_sc.CRSH_BSAT, 0)
            mrk_sc

            mrk_sc              = leftjoin(mrk_sc, select(IM_CRSH_BSAT_Market_df,[:region, :value])  , on = [:region])
                rename!(mrk_sc,   :value => :IM_CRSH_BSAT_Market)
                mrk_sc.IM_CRSH_BSAT_Market = coalesce.(mrk_sc.IM_CRSH_BSAT_Market, 0)            
            mrk_sc
            
            transform!(groupby(mrk_sc, [:region]),             :Vle_TOT_Q => sum => :tot_Vle_TOT_Q)
                    
            mrk_sc.phi_mkt_lc_sec  = NDF_Dst_Prm.(mrk_sc.Vle_TOT_Q ./ mrk_sc.tot_Vle_TOT_Q) .* (coalesce.(mrk_sc.Q_BSAT_Market,0)) .* (coalesce.(mrk_sc.CRSH_BSAT,0))
                   phi_mkt_lc_sec  = Dict((row.region, row.commodity) => BigFloat(row.phi_mkt_lc_sec ) for row in eachrow(mrk_sc))
            
            mrk_sc.phi_mkt_im_sec  = NDF_Dst_Prm.(mrk_sc.Vle_TOT_Q ./ mrk_sc.tot_Vle_TOT_Q) .* (coalesce.(mrk_sc.Q_BSAT_Market,0)) .* (coalesce.(mrk_sc.IM_CRSH_BSAT_Market,0))
                   phi_mkt_im_sec  = Dict((row.region, row.commodity) => BigFloat(row.phi_mkt_im_sec ) for row in eachrow(mrk_sc))
            
        #) phi_LOC_sec(r)         Share of local market in the overall market of secondary commodities in region r   
        #) phi_IMP_sec(r)         Share of imports market in the overall market of secondary commodities in region r  
            mrk_soy               = sort!(mrk[mrk.nest .== "Soy_Cereals",  [:region, :commodity, :Vle_TOT_DC_CRSh, :Vle_M_Crush, :CRSH_BSAT]])
            mrk_soy.phi_LOC_sec   = NDF_Dst_Prm.((mrk_soy.Vle_TOT_DC_CRSh .- mrk_soy.Vle_M_Crush) ./mrk_soy.Vle_TOT_DC_CRSh)  .* (coalesce.(mrk_soy.CRSH_BSAT,0)) 
            mrk_soy.phi_IMP_sec   = NDF_Dst_Prm.((                           mrk_soy.Vle_M_Crush) ./mrk_soy.Vle_TOT_DC_CRSh)  .* (coalesce.(mrk_soy.CRSH_BSAT,0)) 
            mrk_soy

                    phi_LOC_sec   = Dict(row.region => BigFloat(row.phi_LOC_sec) for row in eachrow(mrk_soy))
                    phi_IMP_sec   = Dict(row.region => BigFloat(row.phi_IMP_sec) for row in eachrow(mrk_soy))
            


                     
#  --------------------------------------------------------------------------------------------------
#
#                                    4. MODEL SPECIFICATION
#
#  --------------------------------------------------------------------------------------------------


#  --------------------------------------------------------------------------------------------------
# PART A: DEFINITION OF COUNTERFACTUAL SCENARIOS
#  --------------------------------------------------------------------------------------------------

    local  tau_m_shck_0, tau_m_shck_1, tau_m_base_0, tau_m1_0, tau_m1, tau_x_shck_0, tau_x_shck_1, tau_x_base_0, tau_x1_0, tau_x1, NTM_imp_shck_0, 
           NTM_imp_shck_1, NTM_imp_base_0, NTM_imp1_0, NTM_imp1, NTM_exp_shck_0, NTM_exp_shck_1, NTM_exp_base_0, NTM_exp1_0, NTM_exp1, theta_shck_0, 
           theta_shck_1, theta_base_0, theta1_0, theta1, omega_VA_shck_0, omega_VA_shck_1, omega_VA_base, omega_VA1_0, omega_VA1, omega_IN_shck_0, 
           omega_IN_shck_1, omega_IN_base, omega_IN1_0, omega_LIV_shck_0, omega_LIV_shck_1, omega_LIV_base, omega_LIV1_0, omega_LIV1, Lnd_shck_0, 
           Lnd_shck_1, Lnd_shck_base_0, Lnd_shck1_0, Lnd_shck1, alpha_shck_0, alpha_shck_1, alpha_base_0, alpha1_0, alpha1


    #) Active Shocks            

    #) tau_m1(r,k)        New import tariffs for commodity k in region r   
        tau_m_shck_0           = sort!(info_Shocks[info_Shocks.attribute .== "shock_import_tariff", :])
        tau_m_shck_1           = tau_m_shck_0[:,[:region, :commodity, :value]]  
        tau_m_base_0           = sort!(DataFrame([(k[1], k[2], v) for (k, v) in tau_m0],    [:region, :commodity, :tau_m]))
        tau_m1_0               = outerjoin(tau_m_base_0, tau_m_shck_1, on = [:region, :commodity])
        tau_m1_0.NEW_tau_m     = tau_m1_0.tau_m .+ tau_m1_0.value  
        tau_m1                 = Dict((row.region, row.commodity) => row.NEW_tau_m  for row in eachrow(tau_m1_0))

    #) tau_x1(r,k)        New export tax for commodity k in region r
        tau_x_shck_0           = sort!(info_Shocks[info_Shocks.attribute .== "shock_export_tax", :])
        tau_x_shck_1           = tau_x_shck_0[:,[:region, :commodity, :value]]  
        tau_x_base_0           = sort!(DataFrame([(k[1], k[2], v) for (k, v) in tau_x0],    [:region, :commodity, :tau_x]))
        tau_x1_0               = outerjoin(tau_x_base_0, tau_x_shck_1, on = [:region, :commodity])
        tau_x1_0.NEW_tau_x     = tau_x1_0.tau_x .+ tau_x1_0.value                   
        tau_x1                 = Dict((row.region, row.commodity) => row.NEW_tau_x  for row in eachrow(tau_x1_0))   

    #) NTM_imp1(r,k)      New non-tariff measure for importing commodity k in region r
        NTM_imp_shck_0         = sort!(info_Shocks[info_Shocks.attribute .== "shock_nontariff_import", :])
        NTM_imp_shck_1         = NTM_imp_shck_0[:,[:region, :commodity, :value]]  
        NTM_imp_base_0         = sort!(DataFrame([(k[1], k[2], v) for (k, v) in NTM_imp0],    [:region, :commodity, :NTM_imp]))
        NTM_imp1_0             = outerjoin(NTM_imp_base_0, NTM_imp_shck_1, on = [:region, :commodity])
        NTM_imp1_0.NEW_NTM_imp = NTM_imp1_0.NTM_imp .+ NTM_imp1_0.value
        NTM_imp1               = Dict((row.region, row.commodity) => row.NEW_NTM_imp  for row in eachrow(NTM_imp1_0))

    #) NTM_exp1(r,k)      New non-tariff measure for exporting commodity k in region r
        NTM_exp_shck_0         = sort!(info_Shocks[info_Shocks.attribute .== "shock_nontax_export", :])
        NTM_exp_shck_1         = NTM_exp_shck_0[:,[:region, :commodity, :value]]  
        NTM_exp_base_0         = sort!(DataFrame([(k[1], k[2], v) for (k, v) in NTM_exp0],    [:region, :commodity, :NTM_exp]))
        NTM_exp1_0             = outerjoin(NTM_exp_base_0, NTM_exp_shck_1, on = [:region, :commodity])
        NTM_exp1_0.NEW_NTM_exp = NTM_exp1_0.NTM_exp .+ NTM_exp1_0.value
        NTM_exp1               = Dict((row.region, row.commodity) => row.NEW_NTM_exp  for row in eachrow(NTM_exp1_0))

    #) theta1(r,k)        New land productivity to produce commodity k in region r
        theta_shck_0       = sort!(info_Shocks[info_Shocks.attribute .== "shock_land_prod", :])
        theta_shck_1       = theta_shck_0[:,[:region, :commodity, :value]]   
        theta_base_0       = sort!(DataFrame([(k[1], k[2], v) for (k, v) in theta0],    [:region, :commodity, :theta]))
        theta1_0           = outerjoin(theta_base_0, theta_shck_1, on = [:region, :commodity])
        theta1_0.NEW_theta = theta1_0.theta .+ theta1_0.value
        theta1             = Dict((row.region, row.commodity) => row.NEW_theta  for row in eachrow(theta1_0)) 

    #) omega_VA1(r,k)     New TFP in the generation of value added for commodity k in region r
        omega_VA_shck_0        = sort!(info_Shocks[info_Shocks.attribute .== "shock TFP Productivity Value Added", :])
        omega_VA_shck_1        = omega_VA_shck_0[:,[:region, :commodity, :value]]  
        omega_VA_base          = sort!(DataFrame([(k[1], k[2], v) for (k, v) in omega_VA0],    [:region, :commodity, :omega_VA]))   
        omega_VA1_0            = outerjoin(omega_VA_base, omega_VA_shck_1, on = [:region, :commodity])
        omega_VA1_0.NEW_omega_VA =  omega_VA1_0.omega_VA .+   omega_VA1_0.value                 
        omega_VA1              = Dict((row.region, row.commodity) => row.NEW_omega_VA  for row in eachrow(omega_VA1_0)) 
 
    #) omega_IN1(r,k)     New TFP in the use of intermediates for commodity k in region r
        omega_IN_shck_0        = sort!(info_Shocks[info_Shocks.attribute .== "shock TFP Productivity Intermediates", :])
        omega_IN_shck_1        = omega_IN_shck_0[:,[:region, :commodity, :value]] 
        omega_IN_base          = sort!(DataFrame([(k[1], k[2], v) for (k, v) in omega_IN0],    [:region, :commodity, :omega_IN]))   
        omega_IN1_0            = outerjoin(omega_IN_base, omega_IN_shck_1, on = [:region, :commodity])
        omega_IN1_0.NEW_omega_IN =  omega_IN1_0.omega_IN .+   omega_IN1_0.value       
        omega_IN1              = Dict((row.region, row.commodity) => row.NEW_omega_IN  for row in eachrow(omega_IN1_0)) 

    #) omega_LIV1(r,k)   New TFP in the use of feed for the production of livestock commodity k in region r        
        omega_LIV_shck_0        = sort!(info_Shocks[info_Shocks.attribute .== "shock_TFP_Productivity_Feed_Use_livestock", :])
        omega_LIV_shck_1        = omega_LIV_shck_0[:,[:region, :commodity, :value]] 
        omega_LIV_base          = sort!(DataFrame([(k[1], k[2], v) for (k, v) in omega_LIV0],    [:region, :commodity, :omega_LIV])) 
        omega_LIV1_0            = outerjoin(omega_LIV_base, omega_LIV_shck_1, on = [:region, :commodity])
        omega_LIV1_0.NEW_omega_LIV =  omega_LIV1_0.omega_LIV .+   omega_LIV1_0.value
        omega_LIV1              = Dict((row.region, row.commodity) => row.NEW_omega_LIV  for row in eachrow(omega_LIV1_0)) 

    #) Lnd_shck1(r)       New land supply availability in region r
        Lnd_shck_0             = sort!(info_Shocks[info_Shocks.attribute .== "shock_land_supply", :])
        Lnd_shck_1             = Lnd_shck_0[:,[:region, :value]]  
        Lnd_shck_base_0        = sort!(DataFrame([(k, v) for (k, v) in Lnd_Schk0],    [:region, :Lnd_shck]))
        Lnd_shck1_0            = outerjoin(Lnd_shck_base_0, Lnd_shck_1, on = [:region])
        Lnd_shck1_0.NEW_Lnd_shck = Lnd_shck1_0.Lnd_shck  .+  Lnd_shck1_0.value            
        Lnd_shck1              = Dict(Lnd_shck1_0.region .=> Lnd_shck1_0.NEW_Lnd_shck)

     #) alpha1(r)         New expenditure share in Ag commodities in region r
        alpha_shck_0       = sort!(info_Shocks[info_Shocks.attribute .== "shock_ag_expenditure_share", :])
        alpha_shck_1       = alpha_shck_0[:,[:region, :value]]     
        alpha_base_0       = sort!(DataFrame([(k, v) for (k, v) in alpha0],    [:region, :alpha]))
        alpha1_0           = outerjoin(alpha_base_0, alpha_shck_1, on = :region)
        alpha1_0.NEW_alpha = alpha1_0.alpha .* (1 .+ alpha1_0.value)
        alpha1             = Dict(alpha1_0.region .=> alpha1_0.NEW_alpha) 


    #) Non-Active Shocks 
        Pnld1         =  deepcopy(Pnld0)
        GDP_pc1       =  deepcopy(GDP_pc0)
        pop1          =  deepcopy(pop0)
        P_NA1         =  deepcopy(P_NA0)
        Bgstock1      =  deepcopy(Target_BS)        
        P_NO_FEED1    =  deepcopy(P_NO_FEED0)


#  --------------------------------------------------------------------------------------------------
# PART B: MODEL SPECIFICATION - MCP 
#  --------------------------------------------------------------------------------------------------

    local  BSAT, rk_set_pm_eq, PM_ht, pm_eq, rk_set_paf_eq, k_set_paf_eq_LOC, k_set_paf_eq_IMP, PAF_ht, paf_eq, rk_set_paz_eq, 
           rk_set_paz_eq_LOC, rk_set_paz_eq_IMP, PAZ_ht, paz_eq, rk_set_pa_eq_FOOD, rk_set_pa_eq_FEED, rk_set_pa_eq, PA_ht, pa_eq,
           rnk_set, rn_set, rk_set, r_set, PN_ht, pn_eq, P_AG_ht, PU_ht, PU_eq, rk_set_pe_eq_EX, PE_ht, pe_eq, rk_set_pds_eq, 
           rk_set_pds_eq_FOOD, rk_set_pds_eq_FEED, rk_set_pds_eq_CRSH, PDS_ht, pds_eq, rk_set_pcs_eq, rk_set_pcs_eq_EX, 
           rk_set_pcs_eq_DOM, PCS_ht, pcs_eq,  rk_set_pva_eq, PVA_ht, pva_eq, rk_set_pin_eq, rk_set_pin_eq_DOM_SOY, rk_set_pin_eq_IMP_SOY, 
           PIN_ht, pin_eq, rkg_set_pza_eq, rkg_set_pza_eq_LOC, rkg_set_pza_eq_IMP, PZA_ht, pza_eq, rk_set_pfd_eq, rk_set_pfd_eq_LIV, PFD_ht, 
           pfd_eq, rk_set_plv_eq, rk_set_plv_eq_FEED, PLV_ht, plv_eq, qd_AG_ht, qdAg_eq, qd_NA_ht, qdNA_eq, qd_Nst_ht, qdn_eq, 
           rk_set_qdt_eq_FOOD, rk_set_qdt_eq_FEED, rk_set_qdt_eq, qd_tot_ht, qdt_eq, rk_set_qdxaf_eq, qd_XAF_ht, qdxaf_eq, rk_set_qdxaz_eq, 
           qd_XAZ_ht, qdxaz_eq, rk_set_qdd_eq, qd_Dom_ht, qdd_eq, rk_set_qdm_eq, qd_Imp_ht, qdm_eq, rk_set_qzd_eq, qd_ZDa_ht, qzd_eq, 
           rk_set_qmz_eq, qd_ZIm_ht, qmz_eq, rk_set_qsxss_eq, qs_XSS_ht, qsxss_eq, rk_set_qsxcs_eq, qs_XCS_ht, qsxcs_eq, rk_set_qsd_eq, 
           qs_XDS_ht, qsd_eq, rk_set_qsx_eq, qs_Exp_ht, qsx_eq, rk_set_qsl_eq, qs_Dom_ht, qsl_eq, rk_set_qsc_eq, qs_Crsh_ht, qsc_eq, 
           rk_set_qsz_eq, qs_XDZ_ht, qsz_eq, rk_set_vad_eq, VA_ht, vad_eq, rk_set_int_eq, IN_ht, int_eq, rk_set_landd_eq, qd_LND_ht, 
           landd_eq, rk_set_nolnd_eq, qd_NLD_ht, nolnd_eq, r_set_in_loc_SOY_LC, rk_set_in_loc_eq, qin_LOC_ht, in_loc_eq, r_set_in_imp_SOY_IM, 
           rk_set_in_imp_eq, qin_IMP_ht, in_imp_eq, r_set_crsh_eq_SOY_LC, ry_set_crsh_eq_LOC, r_set_crsh_eq_IMP, ry_set_crsh_eq_IMP, 
           rk_set_crsh_eq, Crsh_ht, crsh_eq, rk_set_qd_nfd_eq, qd_NFD_ht, qd_nfd_eq, rk_set_qd_fdd_eq, 
           qd_FDD_ht, qd_fdd_eq, rkg_set_qd_za_eq, qd_ZA_ht, qd_za_eq, rkg_set_qd_zfl_eq, qd_ZFL_ht, qd_zfl_eq, rkg_set_qd_zfm_eq, qd_ZFM_ht, 
           qd_zfm_eq, rk_set_qd_DC_FOOD_eq, rk_set_qd_DC_FOOD_eq_LC, rk_set_qd_DC_FOOD_eq_IM, qd_DC_FOOD_ht, qd_DC_FOOD_eq, rk_set_qd_DC_FEED_eq_OTR, 
           rk_set_qd_DC_FEED_eq_OTR_LC, rk_set_qd_DC_FEED_eq_OTR_IM, qd_DC_FEED_OTR_ht, qd_DC_FEED_OTR_eq, rk_set_qd_DC_FEED_eq_LIV, 
           rxk_set_qd_DC_FEED_eq_LIV_ZA, rxk_set_qd_DC_FEED_eq_LIV_ZA_LC, rxk_set_qd_DC_FEED_eq_LIV_ZA_IM, qd_DC_FEED_LIV_ht, qd_DC_FEED_LIV_eq,
           rk_set_qd_DC_FEED_eq, qd_DC_FEED_ht, qd_DC_FEED_eq, rk_set_cons_eq_Food, rk_set_cons_eq_Feed, rk_set_cons_eq_Crsh, rk_set_cons_eq, DC_ht, 
           cons_eq, rk_set_loss_eq, LS_ht, loss_eq, rk_set_imp_FEED_eq, rk_set_imp_FEED_eq_OTR, rxk_set_imp_FEED_eq_LIV, qd_IMP_FEED_ht, imp_FEED_eq,
           rk_set_impt_eq, rk_set_impt_eq_Food, rk_set_impt_eq_Feed, rk_set_impt_eq_Othr, r_set_impt_eq_SOY, ry_set_impt_eq_SOY, M_TOT_ht, impt_eq,
           r_set_lands_eq, qs_LND_ht, lands_eq, PLnd_ht, mktLnd_eq, rk_set_qdxss_eq, qd_XSS_ht, qdxss_eq, rk_set_mktSTK_eq, PSS_ht, mktSTK_eq, 
           rk_set_mktcrsh_eq, PC_ht, mktcrsh_eq, k_set_mktWX_eq, rk_set_mktWX_eq, WXtot_ht, mktWX_eq, k_set_mktWM_eq, rk_set_mktWM_eq, WMtot_ht, 
           mktWM_eq, k_set_mktWTrde_eq, PREF_ht, mktWTrde_eq, rk_set_mktQFOOD_eq, PD_ht, mktQFOOD_eq, rk_set_mktQFEED_eq, PZ_ht, mktQFEED_eq,
           rk_set_tds_eq_BS, rk_set_tds_eq_Q, rk_set_tds_eq_IM, rk_set_tds_eq, TDS_ht, tds_eq, rk_set_tdd_eq_DC, rk_set_tdd_eq_EX, rk_set_tdd_eq_ES, 
           rk_set_tdd_eq, TDD_ht, tdd_eq, rk_set_mktQ_eq, PS_ht, mktQ_eq, rk_set_cost_eq, PP_ht, cost_eq, rk_set_zpc_eq, qs_Prd_ht, zpc_eq

            
# BSAT MODEL: MCP model solved using PATH
    BSAT = Model(PATHSolver.Optimizer)
    set_silent(BSAT)


# 1) Active Combinations     
    
    #  --------------------------------------------------------------------------------------------------
    #  1.1  Price Equations 
    #  --------------------------------------------------------------------------------------------------
        #) pm_eq[rk]   
        rk_set_pm_eq        = Set(k for k in keys(IM_BSAT_Market)                  if !ismissing(IM_BSAT_Market[k]))        

        #) paf_eq[rk]   
        rk_set_paf_eq       = Set(k for k in keys(DC_FOOD_BSAT_Market)             if !ismissing(DC_FOOD_BSAT_Market[k]))        
        rk_set_paf_eq_LOC   = Set(k for k in keys(DC_FOOD_BSAT_Market_BUY_LOC)     if !ismissing(DC_FOOD_BSAT_Market_BUY_LOC[k]))        
        rk_set_paf_eq_IMP   = Set(k for k in keys(IM_FOOD_BSAT_Market)             if !ismissing(IM_FOOD_BSAT_Market[k])) 

        #) paz_eq[rk]
        rk_set_paz_eq       = Set(k for k in keys(DC_FEED_OTR_BSAT_Market)         if !ismissing(DC_FEED_OTR_BSAT_Market[k]))        
        rk_set_paz_eq_LOC   = Set(k for k in keys(DC_FEED_OTR_BSAT_Market_BUY_LOC) if !ismissing(DC_FEED_OTR_BSAT_Market_BUY_LOC[k]))        
        rk_set_paz_eq_IMP   = Set(k for k in keys(IM_FEED_OTR_BSAT_Market)         if !ismissing(IM_FEED_OTR_BSAT_Market[k]))        

        #) pa_eq[rk]
        rk_set_pa_eq_FOOD   = Set(k for k in keys(DC_FOOD_BSAT_Market)             if !ismissing(DC_FOOD_BSAT_Market[k]))  
        rk_set_pa_eq_FEED   = Set(k for k in keys(DC_FEED_OTR_BSAT_Market)         if !ismissing(DC_FEED_OTR_BSAT_Market[k]))
        rk_set_pa_eq        = Set(k for k in rk_set_pa_eq_FOOD) ∪ Set(k for k in rk_set_pa_eq_FEED) 

        #) pn_eq[rn]  &  P_AG_eq[r]  &  PU_eq[r]  &  qdAg_eq[r]  &  qdNA_eq[r] & qdn_eq[rn] 
        rnk_set             = [k for (k, v) in phi_n    if !ismissing(v) && !isnan(v) && v >0]
        rn_set              = unique([(x[1], x[2]) for x in rnk_set])
        rk_set              = unique([(x[1], x[3]) for x in rnk_set])
        r_set               = unique([x[1]         for x in rnk_set])

        #) pe_eq[rk]
        rk_set_pe_eq_EX     = Set(k for k in keys(EX_BSAT_Market)                   if !ismissing(EX_BSAT_Market[k]))        

        #) pds_eq[rk]
        rk_set_pds_eq       = Set(k for k in keys(CUR_SUPL_DOM_BSAT_Market)         if !ismissing(CUR_SUPL_DOM_BSAT_Market[k]))        
        rk_set_pds_eq_FOOD  = Set(k for k in keys(DC_FOOD_BSAT_Market)              if !ismissing(DC_FOOD_BSAT_Market[k]))  
        rk_set_pds_eq_FEED  = Set(k for k in keys(DC_FEED_BSAT_Market)              if !ismissing(DC_FEED_BSAT_Market[k]))  
        rk_set_pds_eq_CRSH  = Set(k for k in keys(CRSH_BSAT)                        if !ismissing(CRSH_BSAT[k]))  

        #) pcs_eq[r,k]
        rk_set_pcs_eq       = Set(k for k in keys(CUR_SUPL_BSAT_Market)             if !ismissing(CUR_SUPL_BSAT_Market[k]))
        rk_set_pcs_eq_EX    = Set(k for k in keys(EX_BSAT_Market)                   if !ismissing(EX_BSAT_Market[k]))
        rk_set_pcs_eq_DOM   = Set(k for k in keys(CUR_SUPL_DOM_BSAT_Market)         if !ismissing(CUR_SUPL_DOM_BSAT_Market[k]))

        #) pva_eq[rk]
        rk_set_pva_eq       = Set(k for k in keys(Q_BSAT_Market)                    if !ismissing(Q_BSAT_Market[k])              && k[2] in pri_goods)

        #) pin_eq[rk]
        rk_set_pin_eq         = Set(k for k in keys(Q_BSAT_Market)                  if !ismissing(Q_BSAT_Market[k])              && k[2] in sec_goods)     
        rk_set_pin_eq_DOM_SOY = Set(k for k in keys(CRSH_BSAT)                      if !ismissing(CRSH_BSAT[k])                  && k[2] in soy_inp_goods) 
        rk_set_pin_eq_IMP_SOY = Set(k for k in keys(IM_CRSH_BSAT_Market)            if !ismissing(IM_CRSH_BSAT_Market[k])        && k[2] in soy_inp_goods) 

        #) pza_eq[rkg]
        rkg_set_pza_eq     = Set(k for k in keys(Feed_BSAT_Feed_DA_Liv)             if !ismissing(Feed_BSAT_Feed_DA_Liv[k])        &&  !ismissing(Q_BSAT_Market[(k[1], k[2])]) &&  k[2] in liv_goods)
        rkg_set_pza_eq_LOC = Set(k for k in keys(Feed_BSAT_Feed_DA_Liv_BUY_LOC)     if !ismissing(Feed_BSAT_Feed_DA_Liv_BUY_LOC[k]))
        rkg_set_pza_eq_IMP = Set(k for k in keys(IM_FEED_LIV_comm_BSAT_Market)      if !ismissing(IM_FEED_LIV_comm_BSAT_Market[k]))
         
        #) pfd_eq[rk]
        rk_set_pfd_eq      = Set(k for k in intersect(keys(Q_BSAT_Market), keys(Z_LIV_Feed_BSAT))  if !ismissing(Q_BSAT_Market[k]) &&  !ismissing(Z_LIV_Feed_BSAT[k]) &&  k[2] in liv_goods)
        rk_set_pfd_eq_LIV  = Set(k for k in keys(Feed_BSAT_Feed_DA_Liv)             if !ismissing(Feed_BSAT_Feed_DA_Liv[k]))  

        #) plv_eq[rk]
        rk_set_plv_eq      = Set(k for k in keys(Q_BSAT_Market)                     if !ismissing(Q_BSAT_Market[k])                && k[2] in liv_goods)     
        rk_set_plv_eq_FEED = Set(k for k in intersect(keys(Q_BSAT_Market), keys(Z_LIV_Feed_BSAT))  if !ismissing(Q_BSAT_Market[k]) &&  !ismissing(Z_LIV_Feed_BSAT[k]) &&  k[2] in liv_goods)
        
    #  --------------------------------------------------------------------------------------------------
    #  1.2  Demand Equations
    #  --------------------------------------------------------------------------------------------------
        #) qdt_eq[rk] 
        rk_set_qdt_eq_FOOD  = Set(k for k in keys(DC_FOOD_BSAT_Market)         if !ismissing(DC_FOOD_BSAT_Market[k])         )
        rk_set_qdt_eq_FEED  = Set(k for k in keys(DC_FEED_OTR_BSAT_Market)     if !ismissing(DC_FEED_OTR_BSAT_Market[k])     )
        rk_set_qdt_eq       = Set(k for k in rk_set_qdt_eq_FOOD) ∪ Set(k for k in rk_set_qdt_eq_FEED)
        
        #) qdxaf_eq[rk]
        rk_set_qdxaf_eq     = Set(k for k in keys(DC_FOOD_BSAT_Market)         if !ismissing(DC_FOOD_BSAT_Market[k])         )

        #) qdxaz_eq[rk]
        rk_set_qdxaz_eq     = Set(k for k in keys(DC_FEED_OTR_BSAT_Market)     if !ismissing(DC_FEED_OTR_BSAT_Market[k])     )

        #) qdd_eq(rk)
        rk_set_qdd_eq       = Set(k for k in keys(DC_FOOD_BSAT_Market_BUY_LOC) if !ismissing(DC_FOOD_BSAT_Market_BUY_LOC[k]) )

        #) qdm_eq[rk]     
        rk_set_qdm_eq       = Set(k for k in keys(IM_FOOD_BSAT_Market)         if !ismissing(IM_FOOD_BSAT_Market[k])         )

        #) qzd_eq[rk]
        rk_set_qzd_eq       = Set(k for k in keys(DC_FEED_OTR_BSAT_Market_BUY_LOC) if !ismissing(DC_FEED_OTR_BSAT_Market_BUY_LOC[k]) )

        #) qmz_eq[rk]     
        rk_set_qmz_eq       = Set(k for k in keys(IM_FEED_OTR_BSAT_Market)         if !ismissing(IM_FEED_OTR_BSAT_Market[k])         )

    #  --------------------------------------------------------------------------------------------------
    #  1.3  Supply Equations
    #  --------------------------------------------------------------------------------------------------
        #) qsxss_eq[rk]
        rk_set_qsxss_eq     = Set(k for k in keys(EndStcks_BSAT_Market)        if !ismissing(EndStcks_BSAT_Market[k])         )

        #) qsxcs_eq[rk]
        rk_set_qsxcs_eq     = Set(k for k in keys(CUR_SUPL_BSAT_Market)        if !ismissing(CUR_SUPL_BSAT_Market[k])         )

        #) qsd_eq[rk] 
        rk_set_qsd_eq       = Set(k for k in keys(CUR_SUPL_DOM_BSAT_Market)    if !ismissing(CUR_SUPL_DOM_BSAT_Market[k])     )

        #) qsx_eq[rk]
        rk_set_qsx_eq       = Set(k for k in keys(EX_BSAT_Market)              if !ismissing(EX_BSAT_Market[k])               )        
        
        #) qsl_eq[rk] 
        rk_set_qsl_eq       = Set(k for k in keys(DC_FOOD_BSAT_Market)         if !ismissing(DC_FOOD_BSAT_Market[k])          )        
        
        #) qsc_eq[rk] 
        rk_set_qsc_eq       = Set(k for k in keys(CRSH_BSAT)                   if !ismissing(CRSH_BSAT[k])                    )        
        
        #) qsz_eq[rk]       
        rk_set_qsz_eq       = Set(k for k in keys(DC_FEED_BSAT_Market)         if !ismissing(DC_FEED_BSAT_Market[k])          )

    #  --------------------------------------------------------------------------------------------------
    #  1.4  Crops Production Equations
    #  --------------------------------------------------------------------------------------------------
        #) vad_eq[rk]
        rk_set_vad_eq       = Set(k for k in keys(Q_BSAT_Market)               if !ismissing(Q_BSAT_Market[k])              && k[2] in pri_goods)

        #) int_eq[rk]
        rk_set_int_eq       = Set(k for k in keys(Q_BSAT_Market)               if !ismissing(Q_BSAT_Market[k])              && k[2] in sec_goods)        

        #) landd_eq[rk] 
        rk_set_landd_eq     = Set(k for k in keys(Q_BSAT_Market)               if !ismissing(Q_BSAT_Market[k])              && k[2] in pri_goods)

        #) nolnd_eq[rk]  
        rk_set_nolnd_eq     = Set(k for k in keys(Q_BSAT_Market)               if !ismissing(Q_BSAT_Market[k])              && k[2] in pri_goods)

        #) in_loc_eq[rk] 
        r_set_in_loc_SOY_LC = Set(k[1] for k in keys(CRSH_BSAT)                if  k[2] == "Soybean" && !ismissing(CRSH_BSAT[k]) ) 
        rk_set_in_loc_eq    = Set(k    for k in keys(Q_BSAT_Market)            if !ismissing(Q_BSAT_Market[k])          && k[1] in r_set_in_loc_SOY_LC    &&   k[2] in sec_goods)

        #) in_imp_eq[rk]  
        r_set_in_imp_SOY_IM = Set(k[1] for k in keys(IM_CRSH_BSAT_Market)      if  k[2] == "Soybean" && !ismissing(IM_CRSH_BSAT_Market[k]) ) 
        rk_set_in_imp_eq    = Set(k    for k in keys(Q_BSAT_Market)            if !ismissing(Q_BSAT_Market[k])          && k[1] in r_set_in_imp_SOY_IM    &&   k[2] in sec_goods)

        #) crsh_eq[rk] 
        r_set_crsh_eq_SOY_LC= Set(k[1] for k in keys(CRSH_BSAT)                if  k[2] == "Soybean" && !ismissing(CRSH_BSAT[k]) )
        ry_set_crsh_eq_LOC  = Set(k    for k in keys(Q_BSAT_Market)            if !ismissing(Q_BSAT_Market[k])               && k[1] in r_set_crsh_eq_SOY_LC  &&   k[2] in sec_goods)  
        r_set_crsh_eq_IMP   = Set(k[1] for k in keys(IM_CRSH_BSAT_Market)      if (k[2] == "Soybean" && !ismissing(IM_CRSH_BSAT_Market[k]))) 
        ry_set_crsh_eq_IMP  = Set(k    for k in keys(Q_BSAT_Market)            if !ismissing(Q_BSAT_Market[k])              && k[1] in r_set_crsh_eq_IMP      &&   k[2] in sec_goods)    
        rk_set_crsh_eq      = Set(k    for k in keys(CRSH_BSAT)                if !ismissing(CRSH_BSAT[k]))

    #  --------------------------------------------------------------------------------------------------
    #  1.5  Livestock Production Equations
    #  --------------------------------------------------------------------------------------------------
        #) qd_nfd_eq[rk]
        rk_set_qd_nfd_eq    = Set(k for k in keys(Q_BSAT_Market)               if !ismissing(Q_BSAT_Market[k])              && k[2] in liv_goods)

        #) qd_fdd_eq[rk]
        rk_set_qd_fdd_eq    = Set(k for k in intersect(keys(Q_BSAT_Market), keys(Z_LIV_Feed_BSAT))  if !ismissing(Q_BSAT_Market[k]) &&  !ismissing(Z_LIV_Feed_BSAT[k])  &&  k[2] in liv_goods)

        #) qd_za_eq[rkg]
        rkg_set_qd_za_eq    = Set(k for k in keys(Feed_BSAT_Feed_DA_Liv)       if !ismissing(Feed_BSAT_Feed_DA_Liv[k])      &&  !ismissing(Q_BSAT_Market[(k[1], k[2])]) &&  k[2] in liv_goods)

        #) qd_zfl_eq[rkg]
        rkg_set_qd_zfl_eq   = Set(k for k in keys(Feed_BSAT_Feed_DA_Liv_BUY_LOC)         if !ismissing(Feed_BSAT_Feed_DA_Liv_BUY_LOC[k])          )

        #) qd_zfm_eq[rkg]
        rkg_set_qd_zfm_eq   = Set(k for k in keys(IM_FEED_LIV_comm_BSAT_Market)          if !ismissing(IM_FEED_LIV_comm_BSAT_Market[k])          )

    #  --------------------------------------------------------------------------------------------------
    #  1.6  Market Clearing Condition Equations
    #  --------------------------------------------------------------------------------------------------
        #) qd_DC_FOOD_eq[rk]
        rk_set_qd_DC_FOOD_eq    = Set(k for k in keys(DC_FOOD_BSAT_Market)          if !ismissing(DC_FOOD_BSAT_Market[k])          )
        rk_set_qd_DC_FOOD_eq_LC = Set(k for k in keys(DC_FOOD_BSAT_Market_BUY_LOC)  if !ismissing(DC_FOOD_BSAT_Market_BUY_LOC[k])  )
        rk_set_qd_DC_FOOD_eq_IM = Set(k for k in keys(IM_FOOD_BSAT_Market)          if !ismissing(IM_FOOD_BSAT_Market[k])          )

        #) qd_DC_FEED_OTR_eq[rk]
        rk_set_qd_DC_FEED_eq_OTR       = Set(k for k in keys(DC_FEED_OTR_BSAT_Market)         if !ismissing(DC_FEED_OTR_BSAT_Market[k])         )
        rk_set_qd_DC_FEED_eq_OTR_LC    = Set(k for k in keys(DC_FEED_OTR_BSAT_Market_BUY_LOC) if !ismissing(DC_FEED_OTR_BSAT_Market_BUY_LOC[k]) )
        rk_set_qd_DC_FEED_eq_OTR_IM    = Set(k for k in keys(IM_FEED_OTR_BSAT_Market)         if !ismissing(IM_FEED_OTR_BSAT_Market[k])         )

        #) qd_DC_FEED_LIV_eq[rk]
        rk_set_qd_DC_FEED_eq_LIV        = Set(k for k in keys(DC_FEED_LIV_BSAT_Market)         if !ismissing(DC_FEED_LIV_BSAT_Market[k])         )
        rxk_set_qd_DC_FEED_eq_LIV_ZA    = Set(k for k in keys(Feed_BSAT_Feed_DA_Liv)           if !ismissing(Feed_BSAT_Feed_DA_Liv[k])          &&  k[2] in liv_goods)
        rxk_set_qd_DC_FEED_eq_LIV_ZA_LC = Set(k for k in keys(Feed_BSAT_Feed_DA_Liv_BUY_LOC)   if !ismissing(Feed_BSAT_Feed_DA_Liv_BUY_LOC[k])  &&  k[2] in liv_goods)
        rxk_set_qd_DC_FEED_eq_LIV_ZA_IM = Set(k for k in keys(IM_FEED_LIV_comm_BSAT_Market)    if !ismissing(IM_FEED_LIV_comm_BSAT_Market[k])   &&  k[2] in liv_goods)
 
        #) qd_DC_FEED_eq[rk]
        rk_set_qd_DC_FEED_eq           = Set(k for k in keys(DC_FEED_BSAT_Market)             if !ismissing(DC_FEED_BSAT_Market[k])             )

        #) cons_eq[rk] 
        rk_set_cons_eq_Food = Set(k  for k in keys(DC_FOOD_BSAT_Market)       if !ismissing(DC_FOOD_BSAT_Market[k])) 
        rk_set_cons_eq_Feed = Set(k  for k in keys(DC_FEED_BSAT_Market)       if !ismissing(DC_FEED_BSAT_Market[k])) 
        rk_set_cons_eq_Crsh = Set(k  for k in keys(CRSH_BSAT)                 if !ismissing(CRSH_BSAT[k]))
        rk_set_cons_eq      = Set(k  for k in keys(DC_BSAT_Market)            if !ismissing(DC_BSAT_Market[k]))

        #) loss_eq[rk]
        rk_set_loss_eq      = Set(k  for k in keys(Loss_BSAT_Market)          if !ismissing(Loss_BSAT_Market[k])) 
       
        #) imp_FEED_eq[rk]
        rk_set_imp_FEED_eq      = Set(k  for k in keys(IM_FEED_BSAT_Market)          if !ismissing(IM_FEED_BSAT_Market[k])) 
        rk_set_imp_FEED_eq_OTR  = Set(k  for k in keys(IM_FEED_OTR_BSAT_Market)      if !ismissing(IM_FEED_OTR_BSAT_Market[k])) 
        rxk_set_imp_FEED_eq_LIV = Set(k  for k in keys(IM_FEED_LIV_comm_BSAT_Market) if !ismissing(IM_FEED_LIV_comm_BSAT_Market[k])   &&  k[2] in liv_goods)

        #) impt_eq[rk]
        rk_set_impt_eq      = Set(k  for k in keys(IM_BSAT_Market)            if !ismissing(IM_BSAT_Market[k]))
        rk_set_impt_eq_Food = Set(k  for k in keys(IM_FOOD_BSAT_Market)       if !ismissing(IM_FOOD_BSAT_Market[k])) 
        rk_set_impt_eq_Feed = Set(k  for k in keys(IM_FEED_BSAT_Market)       if !ismissing(IM_FEED_BSAT_Market[k])) 
        rk_set_impt_eq_Othr = Set(k  for k in keys(IM_OTHR_BSAT_Market)       if !ismissing(IM_OTHR_BSAT_Market[k]))
        r_set_impt_eq_SOY   = Set(k[1] for k in keys(IM_CRSH_BSAT_Market)     if (k[2] == "Soybean" && !ismissing(IM_CRSH_BSAT_Market[k]))) 
        ry_set_impt_eq_SOY  = Set(k    for k in keys(Q_BSAT_Market)           if !ismissing(Q_BSAT_Market[k])         && k[1] in r_set_impt_eq_SOY    &&   k[2] in sec_goods)

        # lands_eq[r]  &  mktLnd_eq[r]
        r_set_lands_eq      = Set(k  for k in keys(Area_BSAT_Markets)         if !ismissing(Area_BSAT_Markets[k])) 
                
        #) qdxss_eq[rk]
        rk_set_qdxss_eq     = Set(k  for k in keys(EndStcks_BSAT_Market)      if !ismissing(EndStcks_BSAT_Market[k])) 
                
        #) mktSTK_eq[rk]
        rk_set_mktSTK_eq    = Set(k  for k in keys(EndStcks_BSAT_Market)      if !ismissing(EndStcks_BSAT_Market[k])) 
                
        #) mktcrsh_eq[rk]
        rk_set_mktcrsh_eq   = Set(k  for k in keys(CRSH_BSAT)                 if !ismissing(CRSH_BSAT[k]))  

        #) mktWX_eq[k]   
        k_set_mktWX_eq      = Set(k[2] for k in keys(EX_BSAT_Market)          if !ismissing(EX_BSAT_Market[k]))
        rk_set_mktWX_eq     = Set(k    for k in keys(EX_BSAT_Market)          if !ismissing(EX_BSAT_Market[k]))  

        #) mktWM_eq[k] 
        k_set_mktWM_eq      = Set(k[2] for k in keys(IM_BSAT_Market)          if !ismissing(IM_BSAT_Market[k]))
        rk_set_mktWM_eq     = Set(k    for k in keys(IM_BSAT_Market)          if !ismissing(IM_BSAT_Market[k]))  

        #) mktWTrde_eq[k]
        k_set_mktWTrde_eq   = intersect(k_set_mktWX_eq, k_set_mktWM_eq)

        #) mktQFOOD_eq[rk]
        rk_set_mktQFOOD_eq  = Set(k    for k in keys(DC_FOOD_BSAT_Market)     if !ismissing(DC_FOOD_BSAT_Market[k])) 

        #) mktQFEED_eq[rk]
        rk_set_mktQFEED_eq  = Set(k    for k in keys(DC_FEED_BSAT_Market)     if !ismissing(DC_FEED_BSAT_Market[k])) 

        #) tds_eq[rk]   
        rk_set_tds_eq_BS    = Set(k for k in keys(BsStcks_BSAT_Market)        if !ismissing(BsStcks_BSAT_Market[k]) )
        rk_set_tds_eq_Q     = Set(k for k in keys(Q_BSAT_Market)              if !ismissing(Q_BSAT_Market[k]) )
        rk_set_tds_eq_IM    = Set(k for k in keys(IM_BSAT_Market)             if !ismissing(IM_BSAT_Market[k]) )
        rk_set_tds_eq       = Set(k for k in keys(LC_BSAT_Market)             if !ismissing(LC_BSAT_Market[k]) )

        #) tdd_eq[rk]   
        rk_set_tdd_eq_DC    = Set(k for k in keys(DC_BSAT_Market)             if !ismissing(DC_BSAT_Market[k]) )
        rk_set_tdd_eq_EX    = Set(k for k in keys(EX_BSAT_Market)             if !ismissing(EX_BSAT_Market[k]) )
        rk_set_tdd_eq_ES    = Set(k for k in keys(EndStcks_BSAT_Market)       if !ismissing(EndStcks_BSAT_Market[k]) )
        rk_set_tdd_eq       = Set(k for k in keys(LC_BSAT_Market)             if !ismissing(LC_BSAT_Market[k]) )
    
        #) mktQ_eq[rk]
        rk_set_mktQ_eq      = Set(k for k in keys(LC_BSAT_Market)             if !ismissing(LC_BSAT_Market[k]) )
       
    #  --------------------------------------------------------------------------------------------------
    #  1.7  Zero Profit Conditions
    #  --------------------------------------------------------------------------------------------------
        #) cost_eq[rk]
        rk_set_cost_eq      = Set(k for k in keys(Q_BSAT_Market)              if !ismissing(Q_BSAT_Market[k]) )

        #) zpc_eq[rk]  
        rk_set_zpc_eq       = Set(k for k in keys(Q_BSAT_Market)              if !ismissing(Q_BSAT_Market[k]) )

#  --------------------------------------------------------------------------------------------------

# 2) Variables and starting values    

    #  --------------------------------------------------------------------------------------------------
    #  2.1  Price Equations
    #  --------------------------------------------------------------------------------------------------
        # PM_ht[rk]      1 + perc. change in the import price of commodity k in region r
        @variable(BSAT, PM_ht[rk_set_pm_eq]      >= 0,     start = 1)        

        # PAF_ht[rk]     1 + perc. change in the demand price index for commodity k sold as FOOD in region r (i.e. dom and imp)
        @variable(BSAT, PAF_ht[rk_set_paf_eq]    >= 0,     start = 1)  

        # PAZ_ht[rk]     1 + perc. change in the demand price index for commodity k as sold FEED for OTHER LIVESTOCK in region r (i.e. dom and imp)
        @variable(BSAT, PAZ_ht[rk_set_paz_eq]    >= 0,     start = 1) 

        # PA_ht[rk]      1 + perc. change in the demand price index for commodity k in region r
        @variable(BSAT, PA_ht[rk_set_pa_eq]      >= 0,     start = 1)

        # PN_ht[rn]:     1 + perc. change in the demand price index for commodities in nest n and region r   
        @variable(BSAT, PN_ht[rn_set]            >= 0,     start = 1)

        # P_AG_ht[r]:    1 + perc. change in the demand price index for AG commodities across nests in region r
        @variable(BSAT, P_AG_ht[r_set]           >= 0,     start = 1)

        # PU_ht[r]:      1 + perc. change in the demand price index for all commodities in region r 
        @variable(BSAT, PU_ht[r_set]             >= 0,     start = 1)

        # PE_ht[rk]      1 + perc. change in the export price of commodity k in region r
        @variable(BSAT, PE_ht[rk_set_pe_eq_EX]   >= 0,     start = 1)    

        # PDS_ht[rk]     1 + perc. change in the domestic supply price index for commodity k in region r
        @variable(BSAT, PDS_ht[rk_set_pds_eq]    >= 0,     start = 1) 

        # PCS_ht[rk]     1 + perc. change in the current supply price index for commodity k in region r (i.e. dom and exp)
        @variable(BSAT, PCS_ht[rk_set_pcs_eq]    >= 0,     start = 1) 

        # PVA_ht[rk]     1 + perc. change in the value added price index for primary commodity k in region r
        @variable(BSAT, PVA_ht[rk_set_pva_eq]    >= 0,     start = 1) 

        # PIN_ht[rk]     1 + perc. change in the intermediate goods price index for producing secondary commodity k in region r
        @variable(BSAT, PIN_ht[rk_set_pin_eq]    >= 0,     start = 1)
 
        # PZA_ht[rkg]    1 + perc. change in the commodity g (DOM or IMP) price index used for producing livestock commodity k in region r
        @variable(BSAT, PZA_ht[rkg_set_pza_eq]   >= 0,     start = 1)

        # PFD_ht[rk]     1 + perc. change in the price index of FEED goods used for producing LIVESTOCK commodity k in region r
        @variable(BSAT, PFD_ht[rk_set_pfd_eq]    >= 0,     start = 1)

        # PLV_ht[rk]     1 + perc. change in the price index of FEED and NON FEED inputs used for producing LIVESTOCK commodity k in region r
        @variable(BSAT, PLV_ht[rk_set_plv_eq]    >= 0,     start = 1)

    #  --------------------------------------------------------------------------------------------------
    #  2.2  Demand Equations
    #  --------------------------------------------------------------------------------------------------
        # qd_AG_ht[r]    1 + perc. change in the AG total demand for all commodities in region r
        @variable(BSAT, qd_AG_ht[r_set]          >=0,      start = 1)

        # qd_NA_ht[r]    1 + perc. change in the Non AG total demand for all commodities in region r
        @variable(BSAT, qd_NA_ht[r_set]          >=0,      start = 1)  

        # qd_Nst_ht[rn]  1 + perc. change in the total demand for all commodities in nest n in region r
        @variable(BSAT, qd_Nst_ht[rn_set]        >=0,      start = 1)

        # qd_tot_ht[rk]  1 + perc. change in the total demand of commodity k in region r
        @variable(BSAT, qd_tot_ht[rk_set_qdt_eq] >=0,      start = 1)  

        # qd_XAF_ht[rk]  1 + perc. change in the total demand of commodity k as FOOD in region r
        @variable(BSAT, qd_XAF_ht[rk_set_qdxaf_eq]>=0,     start = 1)  

        # qd_XAZ_ht[rk]  1 + perc. change in the total demand of commodity k as FEED for OTHER LIVESTOCK in region r
        @variable(BSAT, qd_XAZ_ht[rk_set_qdxaz_eq]>=0,     start = 1)  

        # qd_Dom_ht[rk]  1 + perc. change in the domestic demand for commodity k as FOOD in region r
        @variable(BSAT, qd_Dom_ht[rk_set_qdd_eq] >=0,      start = 1)          

        # qd_Imp_ht[rk]  1 + perc. change in the imports demand for commodity k as FOOD in region r
        @variable(BSAT, qd_Imp_ht[rk_set_qdm_eq] >=0,      start = 1)

        # qd_ZDa_ht[rk]  1 + perc. change in the domestic demand for commodity k as FEED for other livestock commodities in region r
        @variable(BSAT, qd_ZDa_ht[rk_set_qzd_eq] >=0,      start = 1)          

        # qd_ZIm_ht[rk]  1 + perc. change in the imports demand for commodity k as FEED for other livestock commodities in region r
        @variable(BSAT, qd_ZIm_ht[rk_set_qmz_eq] >=0,      start = 1)          

    #  --------------------------------------------------------------------------------------------------
    #  2.3  Supply Equations
    #  --------------------------------------------------------------------------------------------------
        # qs_XSS_ht[rk]  1 + perc. change in the supply of inventories of commodity k in region r
        @variable(BSAT, qs_XSS_ht[rk_set_qsxss_eq] >=0,    start = 1)

        # qs_XCS_ht[rk]  1 + perc. change in the current supply of commodity k in region r
        @variable(BSAT, qs_XCS_ht[rk_set_qsxcs_eq] >=0,    start = 1)

        # qs_XDS_ht[rk]  1 + perc. change in the domestic supply of commodity k in region r
        @variable(BSAT, qs_XDS_ht[rk_set_qsd_eq] >=0,      start = 1)
 
        # qs_Exp_ht[rk]  1 + perc. change in the exports supply of commodity k in region r
        @variable(BSAT, qs_Exp_ht[rk_set_qsx_eq] >=0,      start = 1)

        # qs_Dom_ht[rk]  1 + perc. change in the domestic supply of commodity k as FOOD in region r
        @variable(BSAT, qs_Dom_ht[rk_set_qsl_eq] >=0,      start = 1)
      
        # qs_Crsh_ht[rk] 1 + perc. change in the supply of soybeans for crushing in region r
        @variable(BSAT, qs_Crsh_ht[rk_set_qsc_eq]>=0,      start = 1)

        # qs_XDZ_ht[rk]  1 + perc. change in the domestic supply of commodity k as FEED in region r
        @variable(BSAT, qs_XDZ_ht[rk_set_qsz_eq] >=0,      start = 1)

    #  --------------------------------------------------------------------------------------------------
    #  2.4  Crops Production Equations
    #  --------------------------------------------------------------------------------------------------       
        # VA_ht[rk]      1 + perc. change in the value added of primary commodity k in region r
        @variable(BSAT, VA_ht[rk_set_vad_eq]     >=0,      start = 1)

        # IN_ht[rk]      1 + perc. change in the intermediate goods (demand) for producing secondary commodity k in region r
        @variable(BSAT, IN_ht[rk_set_int_eq]     >=0,      start = 1)

        # qd_LND_ht[rk]  1 + perc. change in the demand for land in region r for producing primary commodity k  
        @variable(BSAT, qd_LND_ht[rk_set_landd_eq]>=0,     start = 1)  

        # qd_NLD_ht[rk]  1 + perc. change in the demand for non-land input in region r for producing primary commodity k          
        @variable(BSAT, qd_NLD_ht[rk_set_nolnd_eq]>=0,     start = 1)

        # qin_LOC_ht[rk] 1 + perc. change in the intermediate goods (demand) in local market of crushed soybeans for producing secondary commodity k in region r
        @variable(BSAT, qin_LOC_ht[rk_set_in_loc_eq]>=0,   start = 1)

        # qin_IMP_ht[rk] 1 + perc. change in the intermediate goods (demand) in imports market of soybeans for producing secondary commodity k in region r
        @variable(BSAT, qin_IMP_ht[rk_set_in_imp_eq]>=0,   start = 1)
        
        # Crsh_ht[rk]    1 + perc. change in the demand of soybeans for crushing in region r
        @variable(BSAT, Crsh_ht[rk_set_crsh_eq]  >=0,      start = 1)

    #  --------------------------------------------------------------------------------------------------
    #  2.5  Livestock Production Equations
    #  --------------------------------------------------------------------------------------------------  
        # qd_NFD_ht[rk]  1 + perc. change in the demand for non-feed inputs in the production of livestock commodity k in region r
        @variable(BSAT, qd_NFD_ht[rk_set_qd_nfd_eq]  >=0,  start = 1)

        # qd_FDD_ht[rk]  1 + perc. change in the demand for     feed inputs in the production of livestock commodity k in region r
        @variable(BSAT, qd_FDD_ht[rk_set_qd_fdd_eq]  >=0,  start = 1)

        # qd_ZA_ht[rkg]  1 + perc. change in the demand for     feed input g in the production of livestock commodity k in region r
        @variable(BSAT, qd_ZA_ht[rkg_set_qd_za_eq]   >=0,  start = 1)

        # qd_ZFL_ht[rkg] 1 + perc. change in the LOCAL demand for feed input g in the production of livestock commodity k in region r
        @variable(BSAT, qd_ZFL_ht[rkg_set_qd_zfl_eq] >=0,  start = 1)

        # qd_ZFM_ht[rkg] 1 + perc. change in the IMPORTS demand for feed input g in the production of livestock commodity k in region r
        @variable(BSAT, qd_ZFM_ht[rkg_set_qd_zfm_eq] >=0,  start = 1)

    #  --------------------------------------------------------------------------------------------------
    #  2.6  Market Clearing Condition Equations
    #  --------------------------------------------------------------------------------------------------  
        # qd_DC_FOOD_ht[rk] 1 + perc. change in the demand of commodity k as FOOD in region r
        @variable(BSAT, qd_DC_FOOD_ht[rk_set_qd_DC_FOOD_eq] >=0,  start = 1)

        # qd_DC_FEED_OTR_ht[rk] 1 + perc. change in the demand for commodity k as FEED for OTHER LIVESTOCK in region r
        @variable(BSAT, qd_DC_FEED_OTR_ht[rk_set_qd_DC_FEED_eq_OTR] >=0,  start = 1)

        # qd_DC_FEED_LIV_ht[rk] 1 + perc. change in the demand for commodity k as FEED for USDA LIVESTOCK in region r
        @variable(BSAT, qd_DC_FEED_LIV_ht[rk_set_qd_DC_FEED_eq_LIV] >=0,  start = 1)

        # qd_DC_FEED_ht[rk] 1 + perc. change in the demand for commodity k as FEED in region r
        @variable(BSAT, qd_DC_FEED_ht[rk_set_qd_DC_FEED_eq] >=0,  start = 1)

        # DC_ht[rk]      1 + perc. change in the total consumption of commodity k in region r 
        @variable(BSAT, DC_ht[rk_set_cons_eq]    >=0,      start = 1)
  
        # LS_ht[rk]      1 + perc. change in the total loss of commodity k in region r
        @variable(BSAT, LS_ht[rk_set_loss_eq]    >=0,      start = 1)

        # qd_IMP_FEED_ht[rk] 1 + perc. change in the total imports of commodity k used as FEED in region r
        @variable(BSAT, qd_IMP_FEED_ht[rk_set_imp_FEED_eq]>=0, start = 1)        

        # M_TOT_ht[rk]   1 + perc. change of total imports of commodity k in region r
        @variable(BSAT, M_TOT_ht[rk_set_impt_eq] >=0,      start = 1)

        # qs_LND_ht[r]   1 + perc. change in the supply of land in region r
        @variable(BSAT, qs_LND_ht[r_set_lands_eq]>=0,      start = 1)

        # PLnd_ht[r]     1 + perc. change in the price of land in region r
        @variable(BSAT, PLnd_ht[r_set_lands_eq]  >=0,      start = 1)   

        # qd_XSS_ht[rk]  1 + perc. change in the demand of inventories of commodity k in region r
        @variable(BSAT, qd_XSS_ht[rk_set_qdxss_eq] >= 0,   start = 1)
        
        # PSS_ht[rk]     1 + perc. change in the price of inventories of commodity k in region r 
        @variable(BSAT, PSS_ht[rk_set_mktSTK_eq] >= 0,     start = 1)   

        # PC_ht[rk]      1 + perc. change in the the price of crushed soybeans in region r
        @variable(BSAT, PC_ht[rk_set_mktcrsh_eq] >= 0,     start = 1)

        # WXtot_ht[k]    1 + perc. change in the world exports of commodity k
        @variable(BSAT, WXtot_ht[k_set_mktWX_eq] >=0,      start = 1)

        # WMtot_ht[k]    1 + perc. change in the world imports of commodity k
        @variable(BSAT, WMtot_ht[k_set_mktWM_eq] >=0,      start = 1)

        # PREF_ht[k]      1 + perc. change in the international price of reference of commodity k
        @variable(BSAT, PREF_ht[k_set_mktWTrde_eq]>=0,     start = 1)   

        # PD_ht[rk]       1 + perc. change in the price of commodity k sold as FOOD in region r
        @variable(BSAT, PD_ht[rk_set_mktQFOOD_eq]>=0,      start = 1)   

        # PZ_ht[rk]      1 + perc. change in the price of commodity k sold as FEED in the region r
        @variable(BSAT, PZ_ht[rk_set_mktQFEED_eq]>=0,      start = 1)            

        # TDS_ht[rk]      1 + perc. change in the total supply of commodity k in region r
        @variable(BSAT, TDS_ht[rk_set_tds_eq]    >=0,      start = 1)

        # TDD_ht[rk]      1 + perc. change in the total demand of commodity k in region r 
        @variable(BSAT, TDD_ht[rk_set_tdd_eq]    >=0,      start = 1)   

        # PS_ht[rk]       1 + perc. change in the overall price of commodity k in region r 
        @variable(BSAT, PS_ht[rk_set_mktQ_eq]    >=0,      start = 1)

    #  --------------------------------------------------------------------------------------------------
    #  2.7  Zero Profit Conditions
    #  --------------------------------------------------------------------------------------------------    
        # PP_ht[rk]       1 + perc. change in the producer price (i.e. cost) of producing commodity k in region r
        @variable(BSAT, PP_ht[rk_set_cost_eq]   >=0,       start = 1)

        # qs_Prd_ht[rk]   1 + perc. change on total production of commodity k in region r
        @variable(BSAT, qs_Prd_ht[rk_set_zpc_eq]>=0,       start = 1)

#  --------------------------------------------------------------------------------------------------

# 3) Equations 
            
    #  --------------------------------------------------------------------------------------------------
    #  3.1 Price Equations 
    #  --------------------------------------------------------------------------------------------------
        # pm_eq[rk]     eq. 1 + perc. change in the import price of commodity k in region r
        @expression(BSAT, pm_eq[rk in rk_set_pm_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_pm_eq
                k = rk[2]
                    pm_eq[rk] = PM_ht[rk] - (PREF_ht[k]*((1 + tau_m1[rk])/(1 + tau_m0[rk]))*((1 + NTM_imp1[rk])/(1 + NTM_imp0[rk]))) 
            end   

        # paf_eq[rk]     eq. 1 + perc. change in the demand price index for commodity k sold as FOOD in region r (i.e. dom and imp)
        @expression(BSAT, paf_eq[rk in rk_set_paf_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_paf_eq
                k  = rk[2]
                if     (rk  in  rk_set_paf_eq_LOC)  && (rk  in  rk_set_paf_eq_IMP)
                    paf_eq[rk] = PAF_ht[rk] - ((((1- phi_dFOOD_IMP[rk])*(PD_ht[rk]^(1-sigma_d[k]))) 
                                            +   (    phi_dFOOD_IMP[rk] *(PM_ht[rk]^(1-sigma_d[k]))))^(1/(1-sigma_d[k])))
                elseif (rk  in  rk_set_paf_eq_LOC)  
                    paf_eq[rk] = PAF_ht[rk] - ((((1- phi_dFOOD_IMP[rk])*(PD_ht[rk]^(1-sigma_d[k]))))^(1/(1-sigma_d[k])))                        
                elseif (rk  in  rk_set_paf_eq_IMP)
                    paf_eq[rk] = PAF_ht[rk] - (((    phi_dFOOD_IMP[rk] *(PM_ht[rk]^(1-sigma_d[k]))))^(1/(1-sigma_d[k])))
                end
            end    

        # paz_eq[rk]     eq. 1 + perc. change in the demand price index for commodity k as sold FEED for OTHER LIVESTOCK in region r (i.e. dom and imp)
        @expression(BSAT, paz_eq[rk in rk_set_paz_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_paz_eq
                k  = rk[2]
                if     (rk  in  rk_set_paz_eq_LOC)  && (rk  in  rk_set_paz_eq_IMP)
                    paz_eq[rk] = PAZ_ht[rk] - ((((1- phi_dFEED_IMP[rk])*(PZ_ht[rk]^(1-sigma_d[k]))) 
                                              + (    phi_dFEED_IMP[rk] *(PM_ht[rk]^(1-sigma_d[k]))))^(1/(1-sigma_d[k])))
                elseif (rk  in  rk_set_paz_eq_LOC)                     
                    paz_eq[rk] = PAZ_ht[rk] - ((((1- phi_dFEED_IMP[rk])*(PZ_ht[rk]^(1-sigma_d[k]))))^(1/(1-sigma_d[k])))   
                elseif (rk  in  rk_set_paz_eq_IMP)                     
                    paz_eq[rk] = PAZ_ht[rk] - (((    phi_dFEED_IMP[rk] *(PM_ht[rk]^(1-sigma_d[k]))))^(1/(1-sigma_d[k])))   
                end                       
            end

        # pa_eq[rk]     eq. 1 + perc. change in the demand price index for commodity k in region r
        @expression(BSAT, pa_eq[rk in rk_set_pa_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_pa_eq
                k  = rk[2]
                if         (rk  in  rk_set_pa_eq_FOOD)  && (rk  in  rk_set_pa_eq_FEED)
                    pa_eq[rk] = PA_ht[rk] - (((     phi_VT_FOOD[rk] *(PAF_ht[rk]^(1-sigma_a[k])))
                                            + ((1 - phi_VT_FOOD[rk])*(PAZ_ht[rk]^(1-sigma_a[k]))))^(1/(1-sigma_a[k])))
                elseif     (rk  in  rk_set_pa_eq_FOOD)
                    pa_eq[rk] = PA_ht[rk] - (((     phi_VT_FOOD[rk] *(PAF_ht[rk]^(1-sigma_a[k]))))^(1/(1-sigma_a[k])))
                elseif     (rk  in  rk_set_pa_eq_FEED)
                    pa_eq[rk] = PA_ht[rk] - ((((1 - phi_VT_FOOD[rk])*(PAZ_ht[rk]^(1-sigma_a[k]))))^(1/(1-sigma_a[k])))
                end
            end

        # pn_eq[rn]     eq. 1 + perc. change in the demand price index for commodities in nest n and region r 
        @expression(BSAT, pn_eq[rn in rn_set], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rn in rn_set
                r  = rn[1]
                n  = rn[2]
                local rnk_list
                    rnk_list   = filter(x -> x[1] == r  && x[2] == n , rnk_set)
                    pn_eq[rn]  = PN_ht[rn] - ((sum(phi_n[rnk] * (PA_ht[(r, rnk[3])]^(1-sigma_n[n] )) for rnk in rnk_list))^(1/(1-sigma_n[n])))
            end

        # P_AG_eq[r]    eq. 1 + perc. change in the demand price index for AG commodities across nests in region r 
        @expression(BSAT, P_AG_eq[r in r_set], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for r in r_set
                local rn_list
                    rn_list    = filter(x -> x[1] == r, rn_set)                
                    P_AG_eq[r] = P_AG_ht[r] - ((sum((phi_u[rn]*(PN_ht[rn]^(1 - sigma_u))) for rn in rn_list))^(1/(1 - sigma_u)))               
            end

        # PU_eq[r]      eq. 1 + perc. change in the demand price index for all commodities in region r
        @expression(BSAT, PU_eq[r in r_set], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for r in r_set
                    PU_eq[r] = PU_ht[r] - ((((     alpha0[r] /100)*(P_AG_ht[r]         ^(1-sigma_t)))  
                                        +   (((100-alpha0[r])/100)*((P_NA1[r]/P_NA0[r])^(1-sigma_t))))^(1/(1-sigma_t)))
            end    

        # pe_eq[rk]     eq. 1 + perc. change in the export price of commodity k in region r
        @expression(BSAT, pe_eq[rk in rk_set_pe_eq_EX], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_pe_eq_EX
                k = rk[2]
                    pe_eq[rk] = PE_ht[rk] - (PREF_ht[k]*((1 - tau_x1[rk])/(1 - tau_x0[rk]))*((1 - NTM_exp1[rk])/(1 - NTM_exp0[rk]))) 
            end  

        # pds_eq[rk]    eq. 1 + perc. change in the domestic supply price index for commodity k in region r
        @expression(BSAT, pds_eq[rk in rk_set_pds_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_pds_eq
                k  = rk[2]
                if      (rk  in  rk_set_pds_eq_FOOD) && (rk  in  rk_set_pds_eq_FEED)  && (rk  in  rk_set_pds_eq_CRSH)
                    pds_eq[rk] = PDS_ht[rk]  - ((((1 - (phi_s_FDD[rk] + phi_s_CRH[rk])) *(PD_ht[rk]^(1+omega_c[k])))
                                                +(      phi_s_FDD[rk]                   *(PZ_ht[rk]^(1+omega_c[k])))
                                                +(      phi_s_CRH[rk]                   *(PC_ht[rk]^(1+omega_c[k]))))^(1/(1 + omega_c[k])))
                elseif  (rk  in  rk_set_pds_eq_FOOD) && (rk  in  rk_set_pds_eq_FEED)  
                    pds_eq[rk] = PDS_ht[rk]  - ((((1 - (phi_s_FDD[rk] + phi_s_CRH[rk])) *(PD_ht[rk]^(1+omega_c[k])))
                                                +(      phi_s_FDD[rk]                   *(PZ_ht[rk]^(1+omega_c[k]))))^(1/(1 + omega_c[k])))
                elseif  (rk  in  rk_set_pds_eq_FEED) && (rk  in  rk_set_pds_eq_CRSH)
                    pds_eq[rk] = PDS_ht[rk]  - (((      phi_s_FDD[rk]                   *(PZ_ht[rk]^(1+omega_c[k])))
                                                +(      phi_s_CRH[rk]                   *(PC_ht[rk]^(1+omega_c[k]))))^(1/(1 + omega_c[k])))
                elseif  (rk  in  rk_set_pds_eq_FOOD) && (rk  in  rk_set_pds_eq_CRSH)
                    pds_eq[rk] = PDS_ht[rk]  - ((((1 - (phi_s_FDD[rk] + phi_s_CRH[rk])) *(PD_ht[rk]^(1+omega_c[k])))
                                                +(      phi_s_CRH[rk]                   *(PC_ht[rk]^(1+omega_c[k]))))^(1/(1 + omega_c[k])))
                elseif  (rk  in  rk_set_pds_eq_FOOD) 
                    pds_eq[rk] = PDS_ht[rk]  - ((((1 - (phi_s_FDD[rk] + phi_s_CRH[rk])) *(PD_ht[rk]^(1+omega_c[k]))))^(1/(1 + omega_c[k])))
                elseif  (rk  in  rk_set_pds_eq_FEED)
                    pds_eq[rk] = PDS_ht[rk]  - (((      phi_s_FDD[rk]                   *(PZ_ht[rk]^(1+omega_c[k]))))^(1/(1 + omega_c[k])))                    
                elseif  (rk  in  rk_set_pds_eq_CRSH)
                    pds_eq[rk] = PDS_ht[rk]  - (((      phi_s_CRH[rk]                   *(PC_ht[rk]^(1+omega_c[k]))))^(1/(1 + omega_c[k])))
                end
            end

        # pcs_eq[rk]    eq. 1 + perc. change in the current supply price index for commodity k in region r (i.e. dom and exp)
        @expression(BSAT, pcs_eq[rk in rk_set_pcs_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_pcs_eq 
                    k  = rk[2]                
                if     (rk  in  rk_set_pcs_eq_EX)  &&  (rk in rk_set_pcs_eq_DOM)
                    pcs_eq[rk] = PCS_ht[rk] - (((   phi_s_EXP[rk]  * (PE_ht[rk] ^(1+omega_s[k]))) 
                                        +       ((1-phi_s_EXP[rk]) * (PDS_ht[rk]^(1+omega_s[k]))))^(1/(1+omega_s[k])))                      
                elseif (rk  in  rk_set_pcs_eq_EX)
                    pcs_eq[rk] = PCS_ht[rk] - ((    phi_s_EXP[rk]  * (PE_ht[rk] ^(1+omega_s[k])))^(1/(1+omega_s[k])))   
                elseif (rk  in  rk_set_pcs_eq_DOM) 
                    pcs_eq[rk] = PCS_ht[rk] - (((1-phi_s_EXP[rk])  * (PDS_ht[rk]^(1+omega_s[k])))^(1/(1+omega_s[k])))                    
                end
            end

        # pva_eq[rk]    eq. 1 + perc. change in the value added price index for primary commodity k in region r
        @expression(BSAT, pva_eq[rk in rk_set_pva_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))   
            for rk in rk_set_pva_eq
                r = rk[1]
                k = rk[2]
                    pva_eq[rk] = PVA_ht[rk] - ((( phi_f[rk]  * ((PLnd_ht[r]/((1 + theta1[rk])/(1 + theta0[rk])))^(1-sigma_f[k]))) 
                                            + ((1-phi_f[rk]) * ((Pnld1[r]/Pnld0[r])^(1-sigma_f[k]))))^(1/(1-sigma_f[k])))  
            end  
     
        # pin_eq[rk]    eq. 1 + perc. change in the intermediate goods price index for producing secondary commodity k in region r  
        @expression(BSAT, pin_eq[rk in rk_set_pin_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_pin_eq
                r = rk[1]
                k = rk[2]
                if     ((r, String7("Soybean"))  in  rk_set_pin_eq_DOM_SOY) && ((r, String7("Soybean"))  in   rk_set_pin_eq_IMP_SOY)
                    pin_eq[rk] = PIN_ht[rk] - ((((1 - phi_c_IMP[(r,"Soybean")]) * (PC_ht[(r,"Soybean")]^(1-sigma_c[k])))
                                            +   (     phi_c_IMP[(r,"Soybean")]  * (PM_ht[(r,"Soybean")]^(1-sigma_c[k]))))^(1/(1-sigma_c[k])))                     
                elseif ((r, String7("Soybean"))  in  rk_set_pin_eq_DOM_SOY)
                    pin_eq[rk] = PIN_ht[rk] - ((((1 - phi_c_IMP[(r,"Soybean")]) * (PC_ht[(r,"Soybean")]^(1-sigma_c[k]))))^(1/(1-sigma_c[k])))   
                elseif ((r, String7("Soybean"))  in   rk_set_pin_eq_IMP_SOY)
                    pin_eq[rk] = PIN_ht[rk] - (((     phi_c_IMP[(r,"Soybean")]  * (PM_ht[(r,"Soybean")]^(1-sigma_c[k]))))^(1/(1-sigma_c[k])))                      
                end    
            end

        # pza_eq[rkg]   eq. 1 + perc. change in the commodity g (DOM or IMP) price index used for producing livestock commodity k in region r
        @expression(BSAT, pza_eq[rkg in rkg_set_pza_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rkg in rkg_set_pza_eq
                r = rkg[1]
                k = rkg[2]
                g = rkg[3]
                if      (rkg  in  rkg_set_pza_eq_LOC)  && (rkg  in  rkg_set_pza_eq_IMP)
                    pza_eq[rkg] = PZA_ht[rkg] - ((((1 - phi_z_IMP[rkg])*(PZ_ht[(r,g)]^(1-sigma_w[k])))
                                                 +(     phi_z_IMP[rkg] *(PM_ht[(r,g)]^(1-sigma_w[k]))))^(1/(1-sigma_w[k])))
                elseif  (rkg  in  rkg_set_pza_eq_LOC)  
                    pza_eq[rkg] = PZA_ht[rkg] - ((((1 - phi_z_IMP[rkg])*(PZ_ht[(r,g)]^(1-sigma_w[k]))))^(1/(1-sigma_w[k])))
                elseif  (rkg  in  rkg_set_pza_eq_IMP)
                    pza_eq[rkg] = PZA_ht[rkg] - (((     phi_z_IMP[rkg] *(PM_ht[(r,g)]^(1-sigma_w[k]))))^(1/(1-sigma_w[k])))
                end
            end

        # pfd_eq[rk]     eq. 1 + perc. change in the price index of FEED goods used for producing LIVESTOCK commodity k in region r
        @expression(BSAT, pfd_eq[rk in rk_set_pfd_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_pfd_eq
                r = rk[1]
                k = rk[2]
                local rkg_list
                    rkg_list  = filter(x -> x[1] == r  && x[2] == k , rk_set_pfd_eq_LIV)
                    pfd_eq[rk] = PFD_ht[rk] - (sum((phi_f_INP[rkg]*(PZA_ht[rkg]^(1-sigma_z[k]))) for rkg in rkg_list))^(1/(1-sigma_z[k]))      
            end

        # plv_eq[rk]     eq. 1 + perc. change in the price index of FEED and NON FEED inputs used for producing LIVESTOCK commodity k in region r
        @expression(BSAT, plv_eq[rk in rk_set_plv_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_plv_eq
                k = rk[2]
                if      (rk  in rk_set_plv_eq)  &&  (rk  in  rk_set_plv_eq_FEED)
                    plv_eq[rk] = PLV_ht[rk] - ((((1 - phi_l_FDD[rk])*((P_NO_FEED1[rk]/P_NO_FEED0[rk])^(1-sigma_l[k])))
                                               +(     phi_l_FDD[rk] *((PFD_ht[rk]/((1+omega_LIV1[rk])/(1+omega_LIV0[rk])))^(1-sigma_l[k]))))^(1/(1-sigma_l[k])))                        
                elseif  (rk  in rk_set_plv_eq)
                    plv_eq[rk] = PLV_ht[rk] - ((((1 - phi_l_FDD[rk])*((P_NO_FEED1[rk]/P_NO_FEED0[rk])^(1-sigma_l[k]))))^(1/(1-sigma_l[k])))                        
                elseif  (rk  in rk_set_plv_eq_FEED) 
                    plv_eq[rk] = PLV_ht[rk] - (((     phi_l_FDD[rk] *((PFD_ht[rk]/((1+omega_LIV1[rk])/(1+omega_LIV0[rk])))^(1-sigma_l[k]))))^(1/(1-sigma_l[k]))) 
                end
            end    

    #  --------------------------------------------------------------------------------------------------
    #  3.2  Demand Equations
    #  --------------------------------------------------------------------------------------------------
        # qdAg_eq[r]    eq. 1 + perc. change in the AG total demand for all commodities in region r
        @expression(BSAT, qdAg_eq[r in r_set], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for r in r_set
                    qdAg_eq[r] = qd_AG_ht[r] - (((PU_ht[r]/P_AG_ht[r])^(sigma_t))*((GDP_pc1[r]/GDP_pc0[r])/PU_ht[r])*(pop1[r]/pop0[r]))
            end 

        # qdNA_eq[r]    eq. 1 + perc. change in the Non AG total demand for all commodities in region r
        @expression(BSAT, qdNA_eq[r in r_set], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for r in r_set
                    qdNA_eq[r] = qd_NA_ht[r] - (((PU_ht[r]/(P_NA1[r]/P_NA0[r]))^(sigma_t))*((GDP_pc1[r]/GDP_pc0[r])/PU_ht[r])*(pop1[r]/pop0[r]))
            end 

        # qdn_eq[rn]    eq. 1 + perc. change in the total demand for all commodities in nest n in region r
        @expression(BSAT, qdn_eq[rn in rn_set], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rn in rn_set
                r = rn[1]
                    qdn_eq[rn] = qd_Nst_ht[rn] - (((P_AG_ht[r]/PN_ht[rn])^sigma_u)*qd_AG_ht[r])
            end  

        # qdt_eq[rk]    eq. 1 + perc. change in the total demand of commodity k in region r  
        @expression(BSAT, qdt_eq[rk in rk_set_qdt_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_qdt_eq
                r = rk[1]
                k = rk[2]
                if      k =="Corn" || k =="Sorghum"
                    qdt_eq[rk] = qd_tot_ht[rk] - (((PN_ht[(r,"Cereals")]    /PA_ht[rk])^sigma_n["Cereals"])    *qd_Nst_ht[(r,"Cereals")])
                elseif  k =="SoyMeal" || k =="SoyOil"      
                    qdt_eq[rk] = qd_tot_ht[rk] - (((PN_ht[(r,"Secondary")]  /PA_ht[rk])^sigma_n["Secondary"])  *qd_Nst_ht[(r,"Secondary")]) 
                elseif  k =="Beef" || k =="Pork"  || k =="Poultry"
                    qdt_eq[rk] = qd_tot_ht[rk] - (((PN_ht[(r,"Livestock")]  /PA_ht[rk])^sigma_n["Livestock"])  *qd_Nst_ht[(r,"Livestock")])
                elseif  k =="Cotton"     
                    qdt_eq[rk] = qd_tot_ht[rk] - (qd_Nst_ht[(r,"Other")]) 
                elseif  k =="Barley"     
                    qdt_eq[rk] = qd_tot_ht[rk] - (qd_Nst_ht[(r,"Bly_Cereals")]) 
                elseif  k =="Wheat"     
                    qdt_eq[rk] = qd_tot_ht[rk] - (qd_Nst_ht[(r,"Brd_Cereals")]) 
                elseif  k =="Rice"     
                    qdt_eq[rk] = qd_tot_ht[rk] - (qd_Nst_ht[(r,"Rce_Cereals")])
                elseif  k =="Soybean"     
                    qdt_eq[rk] = qd_tot_ht[rk] - (qd_Nst_ht[(r,"Soy_Cereals")])
                end                                          
            end   

        # qdxaf_eq[rk]   eq. 1 + perc. change in the total demand of commodity k as FOOD in region r
        @expression(BSAT, qdxaf_eq[rk in rk_set_qdxaf_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_qdxaf_eq
                k = rk[2]
                    qdxaf_eq[rk] = qd_XAF_ht[rk] - (((PA_ht[rk]/PAF_ht[rk])^sigma_a[k])*qd_tot_ht[rk]) 
            end              
  
       # qdxaz_eq[rk]   eq. 1 + perc. change in the total demand of commodity k as FEED for OTHER LIVESTOCK in region r
        @expression(BSAT, qdxaz_eq[rk in rk_set_qdxaz_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_qdxaz_eq
                k = rk[2]
                    qdxaz_eq[rk] = qd_XAZ_ht[rk] - (((PA_ht[rk]/PAZ_ht[rk])^sigma_a[k])*qd_tot_ht[rk]) 
            end  

        # qdd_eq[rk]    eq. 1 + perc. change in the domestic demand for commodity k as FOOD in region r
        @expression(BSAT, qdd_eq[rk in rk_set_qdd_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_qdd_eq
                k = rk[2]
                    qdd_eq[rk] = qd_Dom_ht[rk] - (((PAF_ht[rk]/PD_ht[rk])^sigma_d[k])*qd_XAF_ht[rk]) 
            end              
            
        # qdm_eq[rk]    eq. 1 + perc. change in the imports demand for commodity k as FOOD in region r 
        @expression(BSAT, qdm_eq[rk in rk_set_qdm_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_qdm_eq
                k = rk[2]
                    qdm_eq[rk] = qd_Imp_ht[rk] - (((PAF_ht[rk]/PM_ht[rk])^sigma_d[k])*qd_XAF_ht[rk]) 
            end  

        # qzd_eq[rk]     eq. 1 + perc. change in the domestic demand for commodity k as FEED for other livestock commodities in region r
        @expression(BSAT, qzd_eq[rk in rk_set_qzd_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_qzd_eq
                k = rk[2]
                    qzd_eq[rk] = qd_ZDa_ht[rk] - (((PAZ_ht[rk]/PZ_ht[rk])^sigma_d[k])*qd_XAZ_ht[rk]) 
            end  

        # qmz_eq[rk]     eq. 1 + perc. change in the imports demand for commodity k as FEED for other livestock commodities in region r
        @expression(BSAT, qmz_eq[rk in rk_set_qmz_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_qmz_eq
                k = rk[2]
                    qmz_eq[rk] = qd_ZIm_ht[rk] - (((PAZ_ht[rk]/PM_ht[rk])^sigma_d[k])*qd_XAZ_ht[rk]) 
            end  

    #  --------------------------------------------------------------------------------------------------
    #  3.3  Supply Equations
    #  --------------------------------------------------------------------------------------------------    
        # qsxss_eq[rk]  eq. 1 + perc. change in the supply of inventories of commodity k in region r
        @expression(BSAT, qsxss_eq[rk in rk_set_qsxss_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_qsxss_eq
                k = rk[2]
                    qsxss_eq[rk] = qs_XSS_ht[rk] - (((PSS_ht[rk]/PS_ht[rk])^omega_q[k])*TDS_ht[rk])
            end

        # qsxcs_eq[rk]  eq. 1 + perc. change in the current supply of commodity k in region r
        @expression(BSAT, qsxcs_eq[rk in rk_set_qsxcs_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_qsxcs_eq
                k = rk[2]
                    qsxcs_eq[rk] = qs_XCS_ht[rk] - (((PCS_ht[rk]/PS_ht[rk])^omega_q[k])*TDS_ht[rk])
            end 

        # qsd_eq[rk]    eq. 1 + perc. change in the domestic supply of commodity k in region r
        @expression(BSAT, qsd_eq[rk in rk_set_qsd_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))         
            for rk in rk_set_qsd_eq
                k = rk[2]
                    qsd_eq[rk] = qs_XDS_ht[rk] - (((PDS_ht[rk]/PCS_ht[rk])^omega_s[k])*qs_XCS_ht[rk]) 
            end 
   
        # qsx_eq[rk]    eq. 1 + perc. change in the exports supply of commodity k in region r
        @expression(BSAT, qsx_eq[rk in rk_set_qsx_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))  
            for rk in rk_set_qsx_eq
                k = rk[2]
                    qsx_eq[rk] = qs_Exp_ht[rk] - (((PE_ht[rk]/PCS_ht[rk])^omega_s[k])*qs_XCS_ht[rk]) 
            end 

        # qsl_eq[rk]    eq. 1 + perc. change in the domestic supply of commodity k as FOOD in region r
        @expression(BSAT, qsl_eq[rk in rk_set_qsl_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}})) 
            for rk in  rk_set_qsl_eq
                k = rk[2]
                    qsl_eq[rk] = qs_Dom_ht[rk] - (((PD_ht[rk]/PDS_ht[rk])^omega_c[k])*qs_XDS_ht[rk]) 
            end

        # qsc_eq[rk]     eq. 1 + perc. change in the supply of soybeans for crushing in region r
        @expression(BSAT, qsc_eq[rk in rk_set_qsc_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}})) 
            for rk in  rk_set_qsc_eq
                k = rk[2]
                    qsc_eq[rk] = qs_Crsh_ht[rk] - (((PC_ht[rk]/PDS_ht[rk])^omega_c[k])*qs_XDS_ht[rk]) 
            end 

        # qsz_eq[rk]     eq. 1 + perc. change in the domestic supply of commodity k as FEED in region r
        @expression(BSAT, qsz_eq[rk in rk_set_qsz_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}})) 
            for rk in  rk_set_qsz_eq
                k = rk[2]
                    qsz_eq[rk] = qs_XDZ_ht[rk] - (((PZ_ht[rk]/PDS_ht[rk])^omega_c[k])*qs_XDS_ht[rk]) 
            end 

    #  --------------------------------------------------------------------------------------------------
    #  3.4  Crops Production Equations
    #  --------------------------------------------------------------------------------------------------   
        # vad_eq[rk]    eq. 1 + perc. change in the value added of primary commodity k in region r
        @expression(BSAT, vad_eq[rk in rk_set_vad_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_vad_eq
                k = rk[2]
                    vad_eq[rk] = VA_ht[rk] - (((PP_ht[rk]/PVA_ht[rk])^(sigma_i[k]))*(((1+omega_VA1[rk])/(1+omega_VA0[rk]))^(sigma_i[k] -1))*qs_Prd_ht[rk]) 
            end

        # int_eq[rk]    eq. 1 + perc. change in the intermediate goods (demand) for producing secondary commodity k in region r
        @expression(BSAT, int_eq[rk in rk_set_int_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))            
            for rk in rk_set_int_eq
                k = rk[2]
                    int_eq[rk] = IN_ht[rk] - (((PP_ht[rk]/PIN_ht[rk])^sigma_i[k])*(((1 + omega_IN1[rk])/(1 + omega_IN0[rk]))^(sigma_i[k] - 1))*qs_Prd_ht[rk]) 
            end             
  
        # landd_eq[rk]  eq. 1 + perc. change in the demand for land in region r for producing primary commodity k
        @expression(BSAT, landd_eq[rk in rk_set_landd_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))     
            for rk in rk_set_landd_eq
                r = rk[1]
                k = rk[2]
                    landd_eq[rk] = qd_LND_ht[rk] - (((PVA_ht[rk]/PLnd_ht[r])^sigma_f[k]) * VA_ht[rk] * (((1 + theta1[rk])/(1 + theta0[rk]))^(sigma_f[k] -1))) 
            end 

        # nolnd_eq[rk]  eq. 1 + perc. change in the demand for non-land input in region r for producing primary commodity k
        @expression(BSAT, nolnd_eq[rk in rk_set_nolnd_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))     
            for rk in rk_set_nolnd_eq
                r = rk[1]
                k = rk[2]
                    nolnd_eq[rk] = qd_NLD_ht[rk] - (((PVA_ht[rk]/(Pnld1[r]/Pnld0[r]))^sigma_f[k]) * VA_ht[rk]) 
            end 

        # in_loc_eq[rk] eq. 1 + perc. change in the intermediate goods (demand) in local market of crushed soybeans for producing secondary commodity k in region r     
        @expression(BSAT, in_loc_eq[rk in rk_set_in_loc_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}})) 
            for rk in rk_set_in_loc_eq
                r = rk[1] 
                k = rk[2]
                    in_loc_eq[rk] = qin_LOC_ht[rk] - (((PIN_ht[rk]/PC_ht[(r,"Soybean")])^(sigma_c[k]))*IN_ht[rk])
            end    

        # in_imp_eq[rk] eq. 1 + perc. change in the intermediate goods (demand) in imports market of soybeans for producing secondary commodity k in region r
        @expression(BSAT, in_imp_eq[rk in rk_set_in_imp_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}})) 
            for rk in rk_set_in_imp_eq
                r = rk[1] 
                k = rk[2]
                    in_imp_eq[rk] = qin_IMP_ht[rk] - (((PIN_ht[rk]/PM_ht[(r,"Soybean")])^(sigma_c[k]))*IN_ht[rk])
            end  

        # crsh_eq[rk]   eq. 1 + perc. change in the demand of soybeans for crushing in region r
        @expression(BSAT, crsh_eq[rk in rk_set_crsh_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}})) 
            for rk in rk_set_crsh_eq
                r = rk[1]
                if     (r in Set(k[1] for k in ry_set_crsh_eq_LOC))  &&  (r in Set(k[1] for k in ry_set_crsh_eq_IMP))   
                    local ry_list, ry_set_full
                    ry_set_full = ry_set_crsh_eq_LOC ∩ ry_set_crsh_eq_IMP
                    ry_list     = filter(x -> x[1] == r, ry_set_full)
                    crsh_eq[rk] = Crsh_ht[rk] - ((sum(qin_LOC_ht[ry]*phi_mkt_lc_sec[ry] * phi_LOC_sec[r] for ry in ry_list )) 
                                              +  (sum(qin_IMP_ht[ry]*phi_mkt_im_sec[ry] * phi_IMP_sec[r] for ry in ry_list )))                                   
                elseif (r in Set(x[1] for x in ry_set_crsh_eq_LOC))
                    local ry_list, ry_set_full 
                    ry_set_full = ry_set_crsh_eq_LOC 
                    ry_list     = filter(x -> x[1] == r, ry_set_full)
                    crsh_eq[rk] = Crsh_ht[rk] - (sum(qin_LOC_ht[ry]*phi_mkt_lc_sec[ry] * phi_LOC_sec[r]  for ry in ry_list ))

                elseif (r in Set(x[1] for x in ry_set_crsh_eq_IMP)) 
                    local ry_list, ry_set_full
                    ry_set_full = ry_set_crsh_eq_IMP
                    ry_list     = filter(x -> x[1] == r, ry_set_full)
                    crsh_eq[rk] = Crsh_ht[rk] - (sum(qin_IMP_ht[ry]*phi_mkt_im_sec[ry] * phi_IMP_sec[r]  for ry in ry_list ))  
                end
            end

    #  --------------------------------------------------------------------------------------------------
    #  3.5  Livestock Production Equations
    #  --------------------------------------------------------------------------------------------------   
        # qd_nfd_eq[rk]  eq. 1 + perc. change in the demand for non-feed inputs in the production of livestock commodity k in region r
        @expression(BSAT, qd_nfd_eq[rk in rk_set_qd_nfd_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}})) 
            for rk in rk_set_qd_nfd_eq
                k = rk[2] 
                    qd_nfd_eq[rk] = qd_NFD_ht[rk] - (((PLV_ht[rk]/(P_NO_FEED1[rk]/P_NO_FEED0[rk]))^sigma_l[k])*qs_Prd_ht[rk])
            end

        # qd_fdd_eq[rk]  eq. 1 + perc. change in the demand for     feed inputs in the production of livestock commodity k in region r
        @expression(BSAT, qd_fdd_eq[rk in rk_set_qd_fdd_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}})) 
            for rk in rk_set_qd_fdd_eq
                k = rk[2]
                    qd_fdd_eq[rk] = qd_FDD_ht[rk] - (((PLV_ht[rk]/PFD_ht[rk])^sigma_l[k])*qs_Prd_ht[rk]*(((1+omega_LIV1[rk])/(1+omega_LIV0[rk]))^(sigma_l[k]-1)))
            end

        # qd_za_eq[rkg]  eq. 1 + perc. change in the demand for     feed input g in the production of livestock commodity k in region r
        @expression(BSAT, qd_za_eq[rkg in rkg_set_qd_za_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}})) 
            for rkg in rkg_set_qd_za_eq
                r = rkg[1]
                k = rkg[2]
                    qd_za_eq[rkg] = qd_ZA_ht[rkg] - (((PFD_ht[(r,k)]/PZA_ht[rkg])^sigma_z[k])*qd_FDD_ht[(r,k)])
            end

        # qd_zfl_eq[rkg] eq. 1 + perc. change in the LOCAL demand for feed input g in the production of livestock commodity k in region r
        @expression(BSAT, qd_zfl_eq[rkg in rkg_set_qd_zfl_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}})) 
            for rkg in rkg_set_qd_zfl_eq
                r = rkg[1]
                k = rkg[2]
                g = rkg[3]
                    qd_zfl_eq[rkg] = qd_ZFL_ht[rkg] - (((PZA_ht[rkg]/PZ_ht[(r,g)])^sigma_w[k])*qd_ZA_ht[rkg])
            end

        # qd_zfm_eq[rkg] eq. 1 + perc. change in the IMPORTS demand for feed input g in the production of livestock commodity k in region r
        @expression(BSAT, qd_zfm_eq[rkg in rkg_set_qd_zfm_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}})) 
            for rkg in rkg_set_qd_zfm_eq
                r = rkg[1]
                k = rkg[2]
                g = rkg[3]
                    qd_zfm_eq[rkg] = qd_ZFM_ht[rkg] - (((PZA_ht[rkg]/PM_ht[(r,g)])^sigma_w[k])*qd_ZA_ht[rkg])
            end

    #  --------------------------------------------------------------------------------------------------
    #  3.6  Market Clearing Conditions
    #  --------------------------------------------------------------------------------------------------   
        # qd_DC_FOOD_eq[rk] eq. 1 + perc. change in the demand of commodity k as FOOD in region r
        @expression(BSAT, qd_DC_FOOD_eq[rk in rk_set_qd_DC_FOOD_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}})) 
            for rk in rk_set_qd_DC_FOOD_eq
                if     (rk  in  rk_set_qd_DC_FOOD_eq_LC)  &&  (rk  in  rk_set_qd_DC_FOOD_eq_IM) 
                    qd_DC_FOOD_eq[rk] = qd_DC_FOOD_ht[rk] - (((1- phi_dFOOD_IMP[rk])*qd_Dom_ht[rk]) + (phi_dFOOD_IMP[rk] *qd_Imp_ht[rk]))
                elseif (rk  in  rk_set_qd_DC_FOOD_eq_LC) 
                    qd_DC_FOOD_eq[rk] = qd_DC_FOOD_ht[rk] - (((1- phi_dFOOD_IMP[rk])*qd_Dom_ht[rk]))
                elseif (rk  in  rk_set_qd_DC_FOOD_eq_IM) 
                    qd_DC_FOOD_eq[rk] = qd_DC_FOOD_ht[rk] - ((    phi_dFOOD_IMP[rk] *qd_Imp_ht[rk]))
                end
            end

        # qd_DC_FEED_OTR_eq[rk] eq. 1 + perc. change in the demand for commodity k as FEED for OTHER LIVESTOCK in region r
        @expression(BSAT, qd_DC_FEED_OTR_eq[rk in rk_set_qd_DC_FEED_eq_OTR], zero(GenericNonlinearExpr{GenericVariableRef{Float64}})) 
            for rk in rk_set_qd_DC_FEED_eq_OTR
                if     (rk  in  rk_set_qd_DC_FEED_eq_OTR_LC)  &&  (rk  in  rk_set_qd_DC_FEED_eq_OTR_IM)
                    qd_DC_FEED_OTR_eq[rk] = qd_DC_FEED_OTR_ht[rk] - (((1- phi_dFEED_IMP[rk])*qd_ZDa_ht[rk]) + (phi_dFEED_IMP[rk] *qd_ZIm_ht[rk])) 
                elseif (rk  in  rk_set_qd_DC_FEED_eq_OTR_LC)
                    qd_DC_FEED_OTR_eq[rk] = qd_DC_FEED_OTR_ht[rk] - (((1- phi_dFEED_IMP[rk])*qd_ZDa_ht[rk]))
                elseif (rk  in  rk_set_qd_DC_FEED_eq_OTR_IM) 
                    qd_DC_FEED_OTR_eq[rk] = qd_DC_FEED_OTR_ht[rk] - ((    phi_dFEED_IMP[rk] *qd_ZIm_ht[rk]))
                end
            end

        # qd_DC_FEED_LIV_eq[rk] eq. 1 + perc. change in the demand for commodity k as FEED for USDA LIVESTOCK in region r
        @expression(BSAT, qd_DC_FEED_LIV_eq[rk in rk_set_qd_DC_FEED_eq_LIV], zero(GenericNonlinearExpr{GenericVariableRef{Float64}})) 
            for rk in rk_set_qd_DC_FEED_eq_LIV
                r = rk[1]
                k = rk[2]
               if     ((r,k) in Set((el[1],el[3]) for el in rxk_set_qd_DC_FEED_eq_LIV_ZA_LC))  &&  ((r,k) in Set((el[1],el[3]) for el in rxk_set_qd_DC_FEED_eq_LIV_ZA_IM))   
                    local rxk_list
                    rxk_list  = filter(x -> x[1] == r  && x[3] == k , rxk_set_qd_DC_FEED_eq_LIV_ZA)
                    qd_DC_FEED_LIV_eq[rk] = qd_DC_FEED_LIV_ht[rk] - (sum(((((1 - phi_z_IMP[rxk])*qd_ZFL_ht[rxk]) + (phi_z_IMP[rxk] *qd_ZFM_ht[rxk]))*phi_w_INP[rxk]) for rxk in rxk_list)) 
               elseif ((r,k) in Set((el[1],el[3]) for el in rxk_set_qd_DC_FEED_eq_LIV_ZA_LC))
                    local rxk_list
                    rxk_list  = filter(x -> x[1] == r  && x[3] == k , rxk_set_qd_DC_FEED_eq_LIV_ZA)
                    qd_DC_FEED_LIV_eq[rk] = qd_DC_FEED_LIV_ht[rk] - (sum(((((1 - phi_z_IMP[rxk])*qd_ZFL_ht[rxk]))*phi_w_INP[rxk]) for rxk in rxk_list)) 
               elseif ((r,k) in Set((el[1],el[3]) for el in rxk_set_qd_DC_FEED_eq_LIV_ZA_IM))
                    local rxk_list
                    rxk_list  = filter(x -> x[1] == r  && x[3] == k , rxk_set_qd_DC_FEED_eq_LIV_ZA)
                    qd_DC_FEED_LIV_eq[rk] = qd_DC_FEED_LIV_ht[rk] - (sum((((phi_z_IMP[rxk] *qd_ZFM_ht[rxk]))*phi_w_INP[rxk]) for rxk in rxk_list)) 
               end
            end

        # qd_DC_FEED_eq[rk] eq. 1 + perc. change in the demand for commodity k as FEED in region r
        @expression(BSAT, qd_DC_FEED_eq[rk in rk_set_qd_DC_FEED_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}})) 
            for rk in rk_set_qd_DC_FEED_eq
                if      (rk  in  rk_set_qd_DC_FEED_eq_OTR)  &&  (rk  in rk_set_qd_DC_FEED_eq_LIV)
                    qd_DC_FEED_eq[rk] = qd_DC_FEED_ht[rk] - ((qd_DC_FEED_OTR_ht[rk]*phi_w_FDD[rk]) + (qd_DC_FEED_LIV_ht[rk]*(1 - phi_w_FDD[rk])))
                elseif  (rk  in  rk_set_qd_DC_FEED_eq_OTR)
                    qd_DC_FEED_eq[rk] = qd_DC_FEED_ht[rk] - ((qd_DC_FEED_OTR_ht[rk]*     phi_w_FDD[rk] ))
                elseif  (rk  in rk_set_qd_DC_FEED_eq_LIV)      
                    qd_DC_FEED_eq[rk] = qd_DC_FEED_ht[rk] - ((qd_DC_FEED_LIV_ht[rk]*(1 - phi_w_FDD[rk])))
                end
            end

        # cons_eq[rk]   eq. 1 + perc. change in the total consumption of commodity k in region r   
        @expression(BSAT, cons_eq[rk in rk_set_cons_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_cons_eq       
                if      (rk in rk_set_cons_eq_Food)  &&  (rk  in  rk_set_cons_eq_Feed)  &&  (rk  in  rk_set_cons_eq_Crsh)
                    cons_eq[rk] = DC_ht[rk] - ((qd_DC_FOOD_ht[rk]*phi_DFOOD[rk]) + (qd_DC_FEED_ht[rk]*phi_DFEED[rk]) + (Crsh_ht[rk]*phi_DCRSH[rk]))

                elseif  (rk in rk_set_cons_eq_Food)  &&  (rk  in  rk_set_cons_eq_Feed)
                    cons_eq[rk] = DC_ht[rk] - ((qd_DC_FOOD_ht[rk]*phi_DFOOD[rk]) + (qd_DC_FEED_ht[rk]*phi_DFEED[rk]))

                elseif  (rk in rk_set_cons_eq_Food)  &&  (rk  in  rk_set_cons_eq_Crsh) 
                    cons_eq[rk] = DC_ht[rk] - ((qd_DC_FOOD_ht[rk]*phi_DFOOD[rk]) + (Crsh_ht[rk]*phi_DCRSH[rk]))

                elseif  (rk in rk_set_cons_eq_Feed)  &&  (rk  in  rk_set_cons_eq_Crsh)
                    cons_eq[rk] = DC_ht[rk] - ((qd_DC_FEED_ht[rk]*phi_DFEED[rk]) + (Crsh_ht[rk]*phi_DCRSH[rk]))

                elseif  (rk in rk_set_cons_eq_Food)  
                    cons_eq[rk] = DC_ht[rk] - ((qd_DC_FOOD_ht[rk]*phi_DFOOD[rk]))

                elseif  (rk in rk_set_cons_eq_Feed)  
                    cons_eq[rk] = DC_ht[rk] - ((qd_DC_FEED_ht[rk]*phi_DFEED[rk]))

                elseif   (rk in rk_set_cons_eq_Crsh) 
                    cons_eq[rk] = DC_ht[rk] - ((Crsh_ht[rk]*phi_DCRSH[rk]))
                end
            end

        # loss_eq[rk]   eq. 1 + perc. change in the total loss of commodity k in region r
        @expression(BSAT, loss_eq[rk in rk_set_loss_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_loss_eq
                    loss_eq[rk] = LS_ht[rk] - TDS_ht[rk]
            end

        # imp_FEED_eq[rk] eq. 1 + perc. change in the total imports of commodity k used as FEED in region r
        @expression(BSAT, imp_FEED_eq[rk in rk_set_imp_FEED_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_imp_FEED_eq
                r = rk[1]
                k = rk[2]
                if      (rk  in  rk_set_imp_FEED_eq_OTR)  &&  ((r,k) in Set((el[1],el[3]) for el in rxk_set_imp_FEED_eq_LIV))
                    local rxk_list
                    rxk_list  = filter(x -> x[1] == r  && x[3] == k , rxk_set_imp_FEED_eq_LIV)
                    imp_FEED_eq[rk] = qd_IMP_FEED_ht[rk] - ((qd_ZIm_ht[rk]*(1 - phi_MFEED_LIV[rk])) + ((sum((phi_MFEED_LIV_COMM[rxk]*qd_ZFM_ht[rxk]) for rxk in rxk_list))*phi_MFEED_LIV[rk]))
                elseif  (rk  in  rk_set_imp_FEED_eq_OTR)
                    imp_FEED_eq[rk] = qd_IMP_FEED_ht[rk] - ((qd_ZIm_ht[rk]*(1 - phi_MFEED_LIV[rk])))
                elseif  ((r,k) in Set((el[1],el[3]) for el in rxk_set_imp_FEED_eq_LIV))
                    local rxk_list
                    rxk_list  = filter(x -> x[1] == r  && x[3] == k , rxk_set_imp_FEED_eq_LIV)
                    imp_FEED_eq[rk] = qd_IMP_FEED_ht[rk] - (((sum((phi_MFEED_LIV_COMM[rxk]*qd_ZFM_ht[rxk]) for rxk in rxk_list))*phi_MFEED_LIV[rk]))
                end
            end

        # impt_eq[rk]   eq. 1 + perc. change of total imports of commodity k in region r
        @expression(BSAT, impt_eq[rk in rk_set_impt_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_impt_eq
                r = rk[1] 
                k = rk[2]
                if k != "Soybean" || (k == "Soybean"  &&  !(r in Set(x[1] for x in ry_set_impt_eq_SOY)))
                    if      (rk  in  rk_set_impt_eq_Food)  &&  (rk  in  rk_set_impt_eq_Feed)  &&  (rk  in  rk_set_impt_eq_Othr)
                        impt_eq[rk] = M_TOT_ht[rk] - ((qd_Imp_ht[rk]*phi_MFOOD[rk]) + (qd_IMP_FEED_ht[rk]*phi_MFEED[rk]) + ((Target_M_OTHR[rk]/Target_M_OTHR[rk])*phi_MOTHR[rk]))
                    
                    elseif  (rk  in  rk_set_impt_eq_Food)  &&  (rk  in  rk_set_impt_eq_Feed)
                        impt_eq[rk] = M_TOT_ht[rk] - ((qd_Imp_ht[rk]*phi_MFOOD[rk]) + (qd_IMP_FEED_ht[rk]*phi_MFEED[rk]))
                    
                    elseif  (rk  in  rk_set_impt_eq_Food)  &&  (rk  in  rk_set_impt_eq_Othr)
                        impt_eq[rk] = M_TOT_ht[rk] - ((qd_Imp_ht[rk]*phi_MFOOD[rk]) + ((Target_M_OTHR[rk]/Target_M_OTHR[rk])*phi_MOTHR[rk]))
                    
                    elseif  (rk  in  rk_set_impt_eq_Feed)  &&  (rk  in  rk_set_impt_eq_Othr)
                        impt_eq[rk] = M_TOT_ht[rk] - ((qd_IMP_FEED_ht[rk]*phi_MFEED[rk]) + ((Target_M_OTHR[rk]/Target_M_OTHR[rk])*phi_MOTHR[rk]))
                    
                    elseif  (rk  in  rk_set_impt_eq_Food)
                        impt_eq[rk] = M_TOT_ht[rk] - ((qd_Imp_ht[rk]*phi_MFOOD[rk]))
                    
                    elseif  (rk  in  rk_set_impt_eq_Feed)
                        impt_eq[rk] = M_TOT_ht[rk] - ((qd_IMP_FEED_ht[rk]*phi_MFEED[rk]))
                    
                    elseif  (rk  in  rk_set_impt_eq_Othr)
                        impt_eq[rk] = M_TOT_ht[rk] - (((Target_M_OTHR[rk]/Target_M_OTHR[rk])*phi_MOTHR[rk]))
                    end   

                elseif k == "Soybean"  &&  (r in Set(x[1] for x in ry_set_impt_eq_SOY))
                    local ry_list
                    ry_list     = filter(x -> x[1] == r, ry_set_impt_eq_SOY)

                    if      (rk  in  rk_set_impt_eq_Food)  &&  (rk  in  rk_set_impt_eq_Feed)  &&  (rk  in  rk_set_impt_eq_Othr)  
                        impt_eq[rk] = M_TOT_ht[rk] - ((qd_Imp_ht[rk]*phi_MFOOD[rk]) + (qd_IMP_FEED_ht[rk]*phi_MFEED[rk]) + ((Target_M_OTHR[rk]/Target_M_OTHR[rk])*phi_MOTHR[rk])
                                                   + ((sum((qin_IMP_ht[ry]*phi_mkt_im_sec[ry]) for ry  in ry_list))*phi_MCRSH[rk]))

                    elseif  (rk  in  rk_set_impt_eq_Food)  &&  (rk  in  rk_set_impt_eq_Feed)   
                        impt_eq[rk] = M_TOT_ht[rk] - ((qd_Imp_ht[rk]*phi_MFOOD[rk]) + (qd_IMP_FEED_ht[rk]*phi_MFEED[rk])
                                                   + ((sum((qin_IMP_ht[ry]*phi_mkt_im_sec[ry]) for ry  in ry_list))*phi_MCRSH[rk]))

                    elseif  (rk  in  rk_set_impt_eq_Food)  &&  (rk  in  rk_set_impt_eq_Othr)  
                        impt_eq[rk] = M_TOT_ht[rk] - ((qd_Imp_ht[rk]*phi_MFOOD[rk]) + ((Target_M_OTHR[rk]/Target_M_OTHR[rk])*phi_MOTHR[rk])
                                                   + ((sum((qin_IMP_ht[ry]*phi_mkt_im_sec[ry]) for ry  in ry_list))*phi_MCRSH[rk]))

                    elseif  (rk  in  rk_set_impt_eq_Feed)  &&  (rk  in  rk_set_impt_eq_Othr)  
                        impt_eq[rk] = M_TOT_ht[rk] - ((qd_IMP_FEED_ht[rk]*phi_MFEED[rk]) + ((Target_M_OTHR[rk]/Target_M_OTHR[rk])*phi_MOTHR[rk])
                                                   + ((sum((qin_IMP_ht[ry]*phi_mkt_im_sec[ry]) for ry  in ry_list))*phi_MCRSH[rk]))

                    elseif  (rk  in  rk_set_impt_eq_Food)  
                        impt_eq[rk] = M_TOT_ht[rk] - ((qd_Imp_ht[rk]*phi_MFOOD[rk])      
                                                   + ((sum((qin_IMP_ht[ry]*phi_mkt_im_sec[ry]) for ry  in ry_list))*phi_MCRSH[rk]))

                    elseif  (rk  in  rk_set_impt_eq_Feed)  
                        impt_eq[rk] = M_TOT_ht[rk] - ((qd_IMP_FEED_ht[rk]*phi_MFEED[rk]) 
                                                   + ((sum((qin_IMP_ht[ry]*phi_mkt_im_sec[ry]) for ry  in ry_list))*phi_MCRSH[rk]))

                    elseif  (rk  in  rk_set_impt_eq_Othr)  
                        impt_eq[rk] = M_TOT_ht[rk] - (((Target_M_OTHR[rk]/Target_M_OTHR[rk])*phi_MOTHR[rk])
                                                   + ((sum((qin_IMP_ht[ry]*phi_mkt_im_sec[ry]) for ry  in ry_list))*phi_MCRSH[rk]))
                    end
                end
            end

        # lands_eq[r]     eq. 1 + perc. change in the supply of land in region r 
        @expression(BSAT, lands_eq[r in r_set_lands_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for r in r_set_lands_eq
                    lands_eq[r] = qs_LND_ht[r] - (((1 + Lnd_shck1[r])/(1 + Lnd_Schk0[r]))*(PLnd_ht[r]^epsilon_l))
            end

        # mktLnd_eq[r]    eq. market clearing condition for land market in region r 
        @expression(BSAT, mktLnd_eq[r in r_set_lands_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for r in r_set_lands_eq
                local rk_list
                rk_list   = filter(x -> x[1] == r, rk_set_landd_eq)
                    mktLnd_eq[r] = qs_LND_ht[r] - (sum(phi_LND[rk]*qd_LND_ht[rk] for rk  in  rk_list))
            end   

        # qdxss_eq[rk]   eq. 1 + perc. change in the demand of inventories of commodity k in region r   
        @expression(BSAT, qdxss_eq[rk in rk_set_qdxss_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_qdxss_eq
                k = rk[2]
                    qdxss_eq[rk] = qd_XSS_ht[rk] - ((PSS_ht[rk])^(epsilon_q[k])) 
            end

        # mktSTK_eq[rk]  eq. market clearing condition for inventories market of commodity k in region r
        @expression(BSAT, mktSTK_eq[rk in rk_set_mktSTK_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_mktSTK_eq
                    mktSTK_eq[rk] =  qs_XSS_ht[rk] - qd_XSS_ht[rk] 
            end            

        # mktcrsh_eq[rk] eq. market clearing condition for the market of crushed soybeans in region r  
        @expression(BSAT, mktcrsh_eq[rk in rk_set_mktcrsh_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_mktcrsh_eq
                    mktcrsh_eq[rk] = qs_Crsh_ht[rk] - Crsh_ht[rk]
            end

        # mktWX_eq[k]     eq. 1 + perc. change in the world exports of commodity k    
        @expression(BSAT, mktWX_eq[k in k_set_mktWX_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for k in k_set_mktWX_eq
                local rk_list
                    rk_list     = filter(x -> x[2] == k, rk_set_mktWX_eq)
                    mktWX_eq[k] = WXtot_ht[k] - (sum(phi_MKt_EX[rk]*qs_Exp_ht[rk] for rk in rk_list))
            end  

        # mktWM_eq[k]     eq. 1 + perc. change in the world imports of commodity k
        @expression(BSAT, mktWM_eq[k in k_set_mktWM_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))  
            for k in k_set_mktWM_eq
                local rk_list
                rk_list     = filter(x -> x[2] == k, rk_set_mktWM_eq)
                    mktWM_eq[k] = WMtot_ht[k] - (sum(phi_MKt_IM[rk]*M_TOT_ht[rk] for rk in rk_list))                
            end

        # mktWTrde_eq[k]  eq. market clearing condition for the international market of commodity k
        @expression(BSAT, mktWTrde_eq[k in k_set_mktWTrde_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for k in k_set_mktWTrde_eq
                    mktWTrde_eq[k] = WXtot_ht[k] - WMtot_ht[k];  
            end

        # mktQFOOD_eq[rk] eq. market clearing condition for the market of commodity k sold as FOOD in region r  
        @expression(BSAT, mktQFOOD_eq[rk in rk_set_mktQFOOD_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_mktQFOOD_eq
                    mktQFOOD_eq[rk] = qs_Dom_ht[rk] - qd_DC_FOOD_ht[rk]
            end

        # mktQFEED_eq[rk] eq. market clearing condition for the market of commodity k sold as FEED in region r
        @expression(BSAT, mktQFEED_eq[rk in rk_set_mktQFEED_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_mktQFEED_eq
                    mktQFEED_eq[rk] = qs_XDZ_ht[rk] - qd_DC_FEED_ht[rk]
            end

        # tds_eq[rk]      eq. 1 + perc. change in the total supply of commodity k in region r
        @expression(BSAT, tds_eq[rk in rk_set_tds_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_tds_eq

                    if  (rk in rk_set_tds_eq_BS)  &&  (rk in rk_set_tds_eq_Q)  &&  (rk in rk_set_tds_eq_IM) 
                tds_eq[rk] = TDS_ht[rk] - ( (phi_OS_BS[rk]*(Bgstock1[rk]/Target_BS[rk])) + (phi_OS_QPrd[rk]*qs_Prd_ht[rk]) + (phi_OS_M[rk]*M_TOT_ht[rk]))

                elseif  (rk in rk_set_tds_eq_BS)  &&  (rk in rk_set_tds_eq_Q)   
                tds_eq[rk] = TDS_ht[rk] - ( (phi_OS_BS[rk]*(Bgstock1[rk]/Target_BS[rk])) + (phi_OS_QPrd[rk]*qs_Prd_ht[rk]))

                elseif  (rk in rk_set_tds_eq_BS)  &&  rk in rk_set_tds_eq_IM
                tds_eq[rk] = TDS_ht[rk] - ( (phi_OS_BS[rk]*(Bgstock1[rk]/Target_BS[rk])) + (phi_OS_M[rk]*M_TOT_ht[rk]))    

                elseif  (rk in rk_set_tds_eq_Q)   &&  (rk in rk_set_tds_eq_IM)
                tds_eq[rk] = TDS_ht[rk] - ((phi_OS_QPrd[rk]*qs_Prd_ht[rk]) + (phi_OS_M[rk]*M_TOT_ht[rk]))

                elseif  rk in (rk in rk_set_tds_eq_BS)
                tds_eq[rk] = TDS_ht[rk] - (phi_OS_BS[rk]*(Bgstock1[rk]/Target_BS[rk]))   
                
                elseif  (rk in rk_set_tds_eq_Q)
                tds_eq[rk] = TDS_ht[rk] - (phi_OS_QPrd[rk]*qs_Prd_ht[rk])

                elseif  (rk in rk_set_tds_eq_IM) 
                tds_eq[rk] = TDS_ht[rk] - (phi_OS_M[rk]*M_TOT_ht[rk])
                end                 
            end
            
        # tdd_eq[rk]      eq. 1 + perc. change in the total demand of commodity k in region r  
        @expression(BSAT, tdd_eq[rk in rk_set_tdd_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}})) 
            for rk in rk_set_tdd_eq       

                if      (rk  in  rk_set_tdd_eq_DC)  &&  (rk in rk_set_tdd_eq_EX)  &&  (rk in rk_set_tdd_eq_ES)     
                    tdd_eq[rk] = TDD_ht[rk] - ((DC_ht[rk]*phi_OD_Tot_DC[rk]) + (qs_Exp_ht[rk]*phi_OD_EX[rk]) + (qd_XSS_ht[rk]*phi_OD_ES[rk]))

                elseif  (rk  in  rk_set_tdd_eq_DC)  &&  (rk in rk_set_tdd_eq_EX)     
                    tdd_eq[rk] = TDD_ht[rk] - ((DC_ht[rk]*phi_OD_Tot_DC[rk]) + (qs_Exp_ht[rk]*phi_OD_EX[rk]))

                elseif  (rk  in  rk_set_tdd_eq_DC)  &&  (rk in rk_set_tdd_eq_ES)    
                    tdd_eq[rk] = TDD_ht[rk] - ((DC_ht[rk]*phi_OD_Tot_DC[rk]) + (qd_XSS_ht[rk]*phi_OD_ES[rk]))

                elseif  (rk  in  rk_set_tdd_eq_EX)  &&  (rk in rk_set_tdd_eq_ES)    
                    tdd_eq[rk] = TDD_ht[rk] - ((qs_Exp_ht[rk]*phi_OD_EX[rk]) + (qd_XSS_ht[rk]*phi_OD_ES[rk]))

                elseif  (rk  in  rk_set_tdd_eq_DC)     
                    tdd_eq[rk] = TDD_ht[rk] - (DC_ht[rk]*phi_OD_Tot_DC[rk])

                elseif  (rk  in  rk_set_tdd_eq_EX)                    
                    tdd_eq[rk] = TDD_ht[rk] - (qs_Exp_ht[rk]*phi_OD_EX[rk])

                elseif  (rk  in  rk_set_tdd_eq_ES)   
                    tdd_eq[rk] = TDD_ht[rk] - (qd_XSS_ht[rk]*phi_OD_ES[rk])
                end
            end      

        # mktQ_eq[rk]     eq. market clearing condition in the overall market of commodity k in region r
        @expression(BSAT, mktQ_eq[rk in rk_set_mktQ_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}})) 
            for rk in rk_set_mktQ_eq
                mktQ_eq[rk] = TDS_ht[rk] - TDD_ht[rk] 
            end   

    #  --------------------------------------------------------------------------------------------------
    #  3.7  Zero Profit Conditions
    #  -------------------------------------------------------------------------------------------------- 
        # cost_eq[rk]     eq. 1 + perc. change in the cost of producing k in region r        
        @expression(BSAT, cost_eq[rk in rk_set_cost_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}}))
            for rk in rk_set_cost_eq
                k = rk[2]
                if      k in pri_goods
                    cost_eq[rk] = PP_ht[rk] - ((phi_i[k]    *((PVA_ht[rk]/((1 + omega_VA1[rk])/(1 + omega_VA0[rk])))^(1-sigma_i[k])))^(1/(1-sigma_i[k])))
                elseif  k in sec_goods
                    cost_eq[rk] = PP_ht[rk] - (((1-phi_i[k])*((PIN_ht[rk]/((1 + omega_IN1[rk])/(1 + omega_IN0[rk])))^(1-sigma_i[k])))^(1/(1-sigma_i[k])))
                elseif  k in liv_goods
                    cost_eq[rk] = PP_ht[rk] - PLV_ht[rk]
                end
            end  

        # zpc_eq[rk]      eq. zero profit condition of every producer of commodity k in region r
        @expression(BSAT, zpc_eq[rk in rk_set_zpc_eq], zero(GenericNonlinearExpr{GenericVariableRef{Float64}})) 
            for rk in rk_set_zpc_eq
                    zpc_eq[rk] = PP_ht[rk] - PS_ht[rk]
            end
          
#  --------------------------------------------------------------------------------------------------

# 4) Complementary conditions   

    #  --------------------------------------------------------------------------------------------------
    #  4.1 Price Equations
    #  --------------------------------------------------------------------------------------------------  
        for rk in rk_set_pm_eq
            @constraint(BSAT,  pm_eq[rk]  ⟂ PM_ht[rk])
        end       

        for rk in rk_set_paf_eq
            @constraint(BSAT,  paf_eq[rk] ⟂ PAF_ht[rk])
        end   

        for rk in rk_set_paz_eq
            @constraint(BSAT,  paz_eq[rk] ⟂ PAZ_ht[rk])
        end   

        for rk in rk_set_pa_eq
            @constraint(BSAT,  pa_eq[rk]  ⟂ PA_ht[rk])
        end  

        for rn in rn_set
            @constraint(BSAT,  pn_eq[rn]  ⟂ PN_ht[rn])
        end        

        for r in r_set
            @constraint(BSAT,  P_AG_eq[r] ⟂ P_AG_ht[r])
        end

        for r in r_set
            @constraint(BSAT,  PU_eq[r]   ⟂ PU_ht[r])
        end  

        for rk in rk_set_pe_eq_EX
            @constraint(BSAT,  pe_eq[rk]  ⟂ PE_ht[rk])
        end   

        for rk in rk_set_pds_eq
            @constraint(BSAT,  pds_eq[rk] ⟂ PDS_ht[rk])
        end           
        
        for rk in rk_set_pcs_eq
            @constraint(BSAT,  pcs_eq[rk] ⟂ PCS_ht[rk])
        end  

        for rk in rk_set_pva_eq
            @constraint(BSAT,  pva_eq[rk] ⟂ PVA_ht[rk])
        end   

        for rk in rk_set_pin_eq
            @constraint(BSAT,  pin_eq[rk] ⟂ PIN_ht[rk])
        end   

        for rkg in rkg_set_pza_eq
            @constraint(BSAT,  pza_eq[rkg] ⟂ PZA_ht[rkg])
        end         

        for rk in rk_set_pfd_eq
            @constraint(BSAT,  pfd_eq[rk] ⟂ PFD_ht[rk])
        end 

        for rk in rk_set_plv_eq
            @constraint(BSAT,  plv_eq[rk] ⟂ PLV_ht[rk])
        end  

    #  --------------------------------------------------------------------------------------------------
    #  4.2  Demand Equations
    #  --------------------------------------------------------------------------------------------------
        for r in r_set
            @constraint(BSAT,  qdAg_eq[r] ⟂ qd_AG_ht[r])
        end  

        for r in r_set
            @constraint(BSAT,  qdNA_eq[r] ⟂ qd_NA_ht[r])
        end 

        for rn in rn_set
            @constraint(BSAT,  qdn_eq[rn] ⟂ qd_Nst_ht[rn])        
        end    

        for rk in rk_set_qdt_eq
            @constraint(BSAT,  qdt_eq[rk] ⟂ qd_tot_ht[rk])        
        end

        for rk in rk_set_qdxaf_eq
            @constraint(BSAT,  qdxaf_eq[rk] ⟂ qd_XAF_ht[rk])        
        end

        for rk in rk_set_qdxaz_eq
            @constraint(BSAT,  qdxaz_eq[rk] ⟂ qd_XAZ_ht[rk])        
        end
 
        for rk in rk_set_qdd_eq 
            @constraint(BSAT,  qdd_eq[rk] ⟂ qd_Dom_ht[rk]) 
        end 

        for rk in rk_set_qdm_eq 
            @constraint(BSAT,  qdm_eq[rk] ⟂ qd_Imp_ht[rk]) 
        end   

        for rk in rk_set_qzd_eq 
            @constraint(BSAT,  qzd_eq[rk] ⟂ qd_ZDa_ht[rk]) 
        end 

        for rk in rk_set_qmz_eq 
            @constraint(BSAT,  qmz_eq[rk] ⟂ qd_ZIm_ht[rk]) 
        end

    #  --------------------------------------------------------------------------------------------------
    #  4.3  Supply Equations
    #  --------------------------------------------------------------------------------------------------
        for rk in rk_set_qsxss_eq 
            @constraint(BSAT,  qsxss_eq[rk] ⟂ qs_XSS_ht[rk]) 
        end         

        for rk in rk_set_qsxcs_eq 
            @constraint(BSAT,  qsxcs_eq[rk] ⟂ qs_XCS_ht[rk]) 
        end       

        for rk in rk_set_qsd_eq 
            @constraint(BSAT,  qsd_eq[rk] ⟂ qs_XDS_ht[rk]) 
        end   

        for rk in rk_set_qsx_eq 
            @constraint(BSAT,  qsx_eq[rk] ⟂ qs_Exp_ht[rk]) 
        end  
 
        for rk in rk_set_qsl_eq 
            @constraint(BSAT,  qsl_eq[rk] ⟂ qs_Dom_ht[rk]) 
        end 

        for rk in rk_set_qsc_eq 
            @constraint(BSAT,  qsc_eq[rk] ⟂ qs_Crsh_ht[rk]) 
        end 

        for rk in rk_set_qsz_eq 
            @constraint(BSAT,  qsz_eq[rk] ⟂ qs_XDZ_ht[rk]) 
        end 

    #  --------------------------------------------------------------------------------------------------
    #  4.4  Crops Production Equations
    #  --------------------------------------------------------------------------------------------------
        for rk in rk_set_vad_eq 
            @constraint(BSAT,  vad_eq[rk] ⟂ VA_ht[rk]) 
        end  
    
        for rk in rk_set_int_eq 
            @constraint(BSAT,  int_eq[rk] ⟂ IN_ht[rk]) 
        end          

        for rk in rk_set_landd_eq 
            @constraint(BSAT,  landd_eq[rk] ⟂ qd_LND_ht[rk]) 
        end   

        for rk in rk_set_nolnd_eq 
            @constraint(BSAT,  nolnd_eq[rk] ⟂ qd_NLD_ht[rk])                
        end 

        for rk in rk_set_in_loc_eq
            @constraint(BSAT,  in_loc_eq[rk] ⟂ qin_LOC_ht[rk]) 
        end   

        for rk in rk_set_in_imp_eq
            @constraint(BSAT,  in_imp_eq[rk] ⟂ qin_IMP_ht[rk]) 
        end 

        for rk in rk_set_crsh_eq 
            @constraint(BSAT,  crsh_eq[rk] ⟂ Crsh_ht[rk]) 
        end

    #  --------------------------------------------------------------------------------------------------
    #  4.5  Livestock Production Equations
    #  --------------------------------------------------------------------------------------------------
        for rk in rk_set_qd_nfd_eq 
            @constraint(BSAT,  qd_nfd_eq[rk] ⟂ qd_NFD_ht[rk]) 
        end

        for rk in rk_set_qd_fdd_eq 
            @constraint(BSAT,  qd_fdd_eq[rk] ⟂ qd_FDD_ht[rk]) 
        end

        for rkg in rkg_set_qd_za_eq 
            @constraint(BSAT,  qd_za_eq[rkg] ⟂ qd_ZA_ht[rkg]) 
        end

        for rkg in rkg_set_qd_zfl_eq 
            @constraint(BSAT,  qd_zfl_eq[rkg] ⟂ qd_ZFL_ht[rkg]) 
        end

        for rkg in rkg_set_qd_zfm_eq 
            @constraint(BSAT,  qd_zfm_eq[rkg] ⟂ qd_ZFM_ht[rkg]) 
        end

    #  --------------------------------------------------------------------------------------------------
    #  4.6  Market Clearing Condition Equations
    #  --------------------------------------------------------------------------------------------------
        for rk in rk_set_qd_DC_FOOD_eq 
            @constraint(BSAT,  qd_DC_FOOD_eq[rk] ⟂ qd_DC_FOOD_ht[rk]) 
        end

        for rk in rk_set_qd_DC_FEED_eq_OTR 
            @constraint(BSAT,  qd_DC_FEED_OTR_eq[rk] ⟂ qd_DC_FEED_OTR_ht[rk]) 
        end

        for rk in rk_set_qd_DC_FEED_eq_LIV
            @constraint(BSAT,  qd_DC_FEED_LIV_eq[rk] ⟂ qd_DC_FEED_LIV_ht[rk]) 
        end

        for rk in rk_set_qd_DC_FEED_eq
            @constraint(BSAT,  qd_DC_FEED_eq[rk] ⟂ qd_DC_FEED_ht[rk])
        end
 
        for rk in rk_set_cons_eq 
            @constraint(BSAT,  cons_eq[rk] ⟂ DC_ht[rk]) 
        end

        for rk in rk_set_loss_eq 
            @constraint(BSAT,  loss_eq[rk] ⟂ LS_ht[rk]) 
        end

        for rk in rk_set_imp_FEED_eq 
            @constraint(BSAT,  imp_FEED_eq[rk] ⟂ qd_IMP_FEED_ht[rk]) 
        end

        for rk in rk_set_impt_eq 
            @constraint(BSAT,  impt_eq[rk] ⟂ M_TOT_ht[rk]) 
        end

        for r in r_set_lands_eq
            @constraint(BSAT,  lands_eq[r] ⟂ qs_LND_ht[r]) 
        end

        for r in r_set_lands_eq
            @constraint(BSAT,  mktLnd_eq[r] ⟂ PLnd_ht[r]) 
        end   

        for rk in rk_set_qdxss_eq
            @constraint(BSAT,  qdxss_eq[rk] ⟂ qd_XSS_ht[rk]) 
        end   

        for rk in rk_set_mktSTK_eq
            @constraint(BSAT,  mktSTK_eq[rk] ⟂ PSS_ht[rk]) 
        end  

        for rk in rk_set_mktcrsh_eq
            @constraint(BSAT,  mktcrsh_eq[rk] ⟂ PC_ht[rk]) 
        end  

        for k in k_set_mktWX_eq  
            @constraint(BSAT,  mktWX_eq[k] ⟂ WXtot_ht[k])
        end

        for k in k_set_mktWM_eq
            @constraint(BSAT,  mktWM_eq[k] ⟂ WMtot_ht[k])
        end
        
        for k in k_set_mktWTrde_eq
            @constraint(BSAT,  mktWTrde_eq[k] ⟂ PREF_ht[k])
        end

        for rk in rk_set_mktQFOOD_eq
            @constraint(BSAT,  mktQFOOD_eq[rk] ⟂ PD_ht[rk])
        end        

        for rk in rk_set_mktQFEED_eq
            @constraint(BSAT,  mktQFEED_eq[rk] ⟂ PZ_ht[rk])
        end   
         
        for rk in rk_set_tds_eq
            @constraint(BSAT,  tds_eq[rk] ⟂ TDS_ht[rk])
        end

        for rk in rk_set_tdd_eq 
            @constraint(BSAT,  tdd_eq[rk] ⟂ TDD_ht[rk])
        end

        for rk in rk_set_mktQ_eq 
            @constraint(BSAT,  mktQ_eq[rk] ⟂ PS_ht[rk])
        end               

    #  --------------------------------------------------------------------------------------------------
    #  4.7  Zero Profit Conditions
    #  --------------------------------------------------------------------------------------------------   
        for rk in rk_set_cost_eq 
            @constraint(BSAT,  cost_eq[rk] ⟂ PP_ht[rk])
        end

        for rk in rk_set_zpc_eq 
            @constraint(BSAT,  zpc_eq[rk] ⟂ qs_Prd_ht[rk])
        end   
     


       
#  --------------------------------------------------------------------------------------------------
#
#                                    5. MODEL EXECUTION
#
#  --------------------------------------------------------------------------------------------------

mkdir("Results_$i")

    local Solver_Status, Model_Status, tstat, pstat, ok_primal, max_var_length, results_model
    

#1) Solver Attributes  

        # === Core controls ===
        set_optimizer_attribute(BSAT, "output", "yes")
        set_optimizer_attribute(BSAT, "convergence_tolerance", 1e-6)
        set_optimizer_attribute(BSAT, "major_iterations", 500)          
        set_optimizer_attribute(BSAT, "minor_iterations", 17100)        
        set_optimizer_attribute(BSAT, "crash_iteration_limit", 50)
        set_optimizer_attribute(BSAT, "cumulative_iteration_limit", 2147483647)
        set_optimizer_attribute(BSAT, "time_limit", 1.0e10)
        set_optimizer_attribute(BSAT, "interrupt_limit", 5)

        # === Chen damping ===
        set_optimizer_attribute(BSAT, "chen_lambda", 0.8)

        # === Output controls (verbatim from your list) ===
        set_optimizer_attribute(BSAT, "output_errors", "yes")
        set_optimizer_attribute(BSAT, "output_warnings", "no")
        set_optimizer_attribute(BSAT, "output_major_iterations", "yes")
        set_optimizer_attribute(BSAT, "output_major_iterations_frequency", 1)
        set_optimizer_attribute(BSAT, "output_minor_iterations", "yes")
        set_optimizer_attribute(BSAT, "output_minor_iterations_frequency", 500)
        set_optimizer_attribute(BSAT, "output_crash_iterations", "yes")
        set_optimizer_attribute(BSAT, "output_crash_iterations_frequency", 1)
        set_optimizer_attribute(BSAT, "output_initial_point", "no")
        set_optimizer_attribute(BSAT, "output_initial_statistics", "no")
        set_optimizer_attribute(BSAT, "output_initial_point_statistics", "yes")
        set_optimizer_attribute(BSAT, "output_initial_scaling_statistics", "yes")
        set_optimizer_attribute(BSAT, "output_final_point", "no")
        set_optimizer_attribute(BSAT, "output_final_statistics", "yes")
        set_optimizer_attribute(BSAT, "output_final_point_statistics", "yes")
        set_optimizer_attribute(BSAT, "output_final_scaling_statistics", "no")
        set_optimizer_attribute(BSAT, "output_final_degeneracy_statistics", "no")
        set_optimizer_attribute(BSAT, "output_final_summary", "yes")
        set_optimizer_attribute(BSAT, "output_maximum_zero_log", 10)
        set_optimizer_attribute(BSAT, "output_maximum_zero_listing", 1000)
        set_optimizer_attribute(BSAT, "output_restart_log", "yes")
        set_optimizer_attribute(BSAT, "output_options", "no")
        set_optimizer_attribute(BSAT, "output_linear_model", "no")

        # === Presolve, scaling, line search, crash, NMS, etc. ===
        set_optimizer_attribute(BSAT, "presolve", "yes")
        set_optimizer_attribute(BSAT, "output_presolve_level", 1)
        set_optimizer_attribute(BSAT, "gradient_step_limit", 5)
        set_optimizer_attribute(BSAT, "gradient_searchtype", "arc")
        set_optimizer_attribute(BSAT, "crash_method", "pnewton")
        set_optimizer_attribute(BSAT, "crash_perturb", "yes")
        set_optimizer_attribute(BSAT, "crash_searchtype", "line")
        set_optimizer_attribute(BSAT, "crash_minimum_dimension", 1)
        set_optimizer_attribute(BSAT, "crash_nbchange_limit", 1)
        set_optimizer_attribute(BSAT, "nms", "yes")
        set_optimizer_attribute(BSAT, "nms_memory_size", 10)
        set_optimizer_attribute(BSAT, "nms_mstep_frequency", 10)
        set_optimizer_attribute(BSAT, "nms_initial_reference_factor", 20)
        set_optimizer_attribute(BSAT, "nms_searchtype", "line")
        set_optimizer_attribute(BSAT, "nms_maximum_watchdogs", 5)
        set_optimizer_attribute(BSAT, "proximal_perturbation", 0)
        set_optimizer_attribute(BSAT, "merit_function", "fischer")
        set_optimizer_attribute(BSAT, "crash_merit_function", "fischer")
        set_optimizer_attribute(BSAT, "lemke_start", "automatic")
        set_optimizer_attribute(BSAT, "lemke_start_type", "slack")
        set_optimizer_attribute(BSAT, "lemke_rank_deficiency_iterations", 10)
        set_optimizer_attribute(BSAT, "scale", 1)

#  --------------------------------------------------------------------------------------------------
                                                                 
#2) Model Optimization
    open("Results_$i/Solver_Status_Model_$i.txt", "w") do file
        optimize!(BSAT)
        Solver_Status = primal_status(BSAT)
        Model_Status  = termination_status(BSAT) 
                
        println("Solver status: ", Solver_Status)
        println("Model status: ", Model_Status)
        println(" ")
        println(" ")        
        
        # Checking the solution of the model
            if Solver_Status !== nothing
                println(file, "Solver status: ", Solver_Status)
            else
                println(file, "Solver status: No output")
            end
                
            if Model_Status !== nothing
                println(file, "Model status: ", Model_Status)
            else
                println(file, "Model status: No output")
            end   
    end            
                
#  --------------------------------------------------------------------------------------------------

#3) Printing and Saving Results

    #3.1) Printing results 
    #NOTE: The model reports results when a solution is found, that is when a simulation is feasible. 
    #      Otherwise, no results are generated, and the model proceeds to the next year's simulation.
        is_solved_and_feasible(BSAT)
            if (is_solved_and_feasible(BSAT))
               println("Solution found")
            end
    
        tstat     = termination_status(BSAT)
        pstat     = primal_status(BSAT)
        ok_primal = pstat in (MathOptInterface.FEASIBLE_POINT, MathOptInterface.NEARLY_FEASIBLE_POINT)

            if     tstat == MathOptInterface.TIME_LIMIT && ok_primal
                @warn "Time limit hit; using feasible incumbent" termination_status=tstat primal_status=pstat
            elseif tstat in (MathOptInterface.OPTIMAL, MathOptInterface.LOCALLY_SOLVED) && ok_primal
                println("Simulation is generated for baseline projections of the year $i")
                println("  ")
                println("  ")
            else
                @warn "Simulation CANNOT be generated for baseline projections of the year $i" termination_status=tstat primal_status=pstat
                println("  ")
                println("  ")
                continue
            end

        max_var_length = maximum(length(name(var)) for var in all_variables(BSAT))
        for var in all_variables(BSAT)
            local var_name, val, cleaned_var_name 
            var_name         = name(var)
            val              = value(var)       
            cleaned_var_name = replace(var_name, r"String\d+\(\"(.*?)\"\)" => s"\1")
###         @printf("Variable %-*s = %.4f\n", max_var_length, cleaned_var_name, val)
        end


    #3.2) Saving the results of the simulation - .csv   
        results_model = DataFrame(Variable=String[], Value=Float64[])
            for var in all_variables(BSAT)
                local var_name, var_value, cleaned_var_name
                var_name         = string(var)  
                var_value        = value(var)   
                cleaned_var_name = replace(var_name, r"String\d+\(\"(.*?)\"\)" => s"\1")
                push!(results_model, (cleaned_var_name,  var_value))  
            end
        CSV.write("Results_$i/All Results.csv", results_model)


                         
    
#  --------------------------------------------------------------------------------------------------
#
#                                    6. MODEL OUTPUT
#
#  --------------------------------------------------------------------------------------------------

mkdir("Output_$i")

    local  df_A0, df_A1, df_BS0, df_Q0, df_Q1, df_M0, df_M1, df_DC0, df_DC1, df_DCFOOD0, df_DCFOOD1, df_DCFEED0, df_DCFEED1, df_Crsh0, df_Crsh1,
           df_X0, df_X1, df_ES0, df_ES1, df_Loss0, df_Loss1, df_E0, df_E1, df_E2, df_E3, df_Y0, df_Mkt, df_output_sol, solution_df, data_solution, 
           tab_exog_A, data_parameters_calb_A, tab_exog_B, data_parameters_calb_B, data_parameters_calb, data_exogenous_sol, 
           METADATA 


#1) Loading key results        

    #1.1) Area - A
        df_A0 = DataFrame(region=String[], commodity=String[], A_ht=BigFloat[])
            for rk in rk_set_landd_eq
                r=rk[1] 
                k=rk[2]
                value_qd_LND_ht = value(qd_LND_ht[rk])  
                push!(df_A0, (r, k, value_qd_LND_ht))             
            end  
        df_A1    = outerjoin(df_A0, Target_A_df, on = [:region, :commodity])
        #NOTE: All region-commodity combinations for which the USDA reports that area is zero, the model DOES NOT predict a result. It reports "missing".
        #      This is correct because the model only considers combinations with positive values. Accordingly, these missing values are dropped below.   
        filter!(:A_ht => x -> !ismissing(x), df_A1)
        rename!(df_A1, :value => :Target_A)
        df_A1.A1 = df_A1.Target_A .* df_A1.A_ht
        

    #1.2) Beginning Stocks
        df_BS0 = deepcopy(Target_BS_df)
        filter!(:value => x -> !ismissing(x) && x != 0, df_BS0)
        rename!(df_BS0, :value => :Target_BS)


    #1.3) Production - Q
        df_Q0 = DataFrame(region=String[], commodity=String[], Q_ht=BigFloat[])
            for rk in rk_set_zpc_eq
                r=rk[1] 
                k=rk[2]   
                value_Qs_Prd_ht = value(qs_Prd_ht[rk])  
                push!(df_Q0, (r, k, value_Qs_Prd_ht))             
            end 
        df_Q1   = outerjoin(df_Q0, Target_Q_df, on = [:region, :commodity])
        #NOTE: All region-commodity combination for which the USDA reports that production is zero, the model DOES NOT predict a result. It reports "missing".
        #      This is correct because the model only considers combinations with positive values. Accordingly, these missing values are dropped below.   
        filter!(:Q_ht => x -> !ismissing(x), df_Q1) 
        rename!(df_Q1, :value => :Target_Q)
        df_Q1.Q1= df_Q1.Target_Q .* df_Q1.Q_ht

        
    #1.4) Imports - M 
        df_M0 = DataFrame(region=String[], commodity=String[], M_ht=BigFloat[])
            for rk in rk_set_impt_eq
                r=rk[1] 
                k=rk[2]
                value_M_TOT_ht = value(M_TOT_ht[rk])  
                push!(df_M0, (r, k, value_M_TOT_ht))             
            end     
        df_M1   = outerjoin(df_M0, Target_M_df, on = [:region, :commodity])
        #NOTE: All region-commodity combinations for which the USDA reports that imports are zero, the model DOES NOT predict a result. It reports "missing".
        #      This is correct because the model only considers combinations with positive values. Accordingly, these missing values are dropped below.   
        filter!(:M_ht => x -> !ismissing(x), df_M1) 
        rename!(df_M1, :value => :Target_M)
        df_M1.M1= df_M1.Target_M .* df_M1.M_ht


    #1.5) Total Consumption - DC
        df_DC0 = DataFrame(region=String[], commodity=String[], DC_ht=BigFloat[])
            for rk in rk_set_cons_eq
                r=rk[1] 
                k=rk[2]
                value_DC_ht = value(DC_ht[rk])  
                push!(df_DC0, (r, k, value_DC_ht))             
            end          
        df_DC1    = outerjoin(df_DC0, Target_DC_df, on = [:region, :commodity])
        #NOTE: All region-commodity combinations for which the USDA reports that total consumption is zero, the model DOES NOT predict a result. It reports "missing".
        #      This is correct because the model only considers combinations with positive values. Accordingly, these missing values are dropped below.   
        filter!(:DC_ht => x -> !ismissing(x), df_DC1) 
        rename!(df_DC1,  :value => :Target_DC) 
        df_DC1.DC1 = df_DC1.Target_DC .* df_DC1.DC_ht


    #1.6) FOOD Consumption - DC FOOD
        df_DCFOOD0 = DataFrame(region=String[], commodity=String[], DCFOOD_ht=BigFloat[])
            for rk in rk_set_qd_DC_FOOD_eq
                r=rk[1] 
                k=rk[2]
                value_DCFOOD_ht = value(qd_DC_FOOD_ht[rk])  
                push!(df_DCFOOD0, (r, k, value_DCFOOD_ht))             
            end          
        df_DCFOOD1    = outerjoin(df_DCFOOD0, Target_DC_FOOD_df, on = [:region, :commodity])
        #NOTE: All region-commodity combinations for which the USDA reports that FOOD consumption is zero, the model DOES NOT predict a result. It reports "missing".
        #      This is correct because the model only considers combinations with positive values. Accordingly, these missing values are dropped below.   
        filter!(:DCFOOD_ht => x -> !ismissing(x), df_DCFOOD1) 
        rename!(df_DCFOOD1,  :value => :Target_DC_FOOD) 
        df_DCFOOD1.DCFOOD1 = df_DCFOOD1.Target_DC_FOOD .* df_DCFOOD1.DCFOOD_ht


    #1.7) FEED Consumption - DC FEED
        df_DCFEED0 = DataFrame(region=String[], commodity=String[], DCFEED_ht=BigFloat[])
            for rk in rk_set_qd_DC_FEED_eq
                r=rk[1] 
                k=rk[2]
                value_DCFEED_ht = value(qd_DC_FEED_ht[rk])  
                push!(df_DCFEED0, (r, k, value_DCFEED_ht))             
            end 
        df_DCFEED1    = outerjoin(df_DCFEED0, Target_DC_FEED_df, on = [:region, :commodity])
        #NOTE: All region-commodity combinations for which the USDA reports that FEED consumption is zero, the model DOES NOT predict a result. It reports "missing".
        #      This is correct because the model only considers combinations with positive values. Accordingly, these missing values are dropped below.   
        filter!(:DCFEED_ht => x -> !ismissing(x), df_DCFEED1) 
        rename!(df_DCFEED1,  :value => :Target_DC_FEED) 
        df_DCFEED1.DCFEED1 = df_DCFEED1.Target_DC_FEED .* df_DCFEED1.DCFEED_ht


    #1.8) Crushing - Crsh
        df_Crsh0 = DataFrame(region=String[], commodity=String[], Crsh_ht=BigFloat[])
        for rk in rk_set_crsh_eq
            r=rk[1] 
            k=rk[2]
            value_Crsh_ht = value(Crsh_ht[rk])  
            push!(df_Crsh0, (r, k, value_Crsh_ht))             
        end  
        df_Crsh1      = outerjoin(df_Crsh0, Target_Crsh_df, on = [:region, :commodity])
        #NOTE: All region-commodity combinations for which the USDA reports that crushing is zero, the model DOES NOT predict a result. It reports "missing".
        #      This is correct because the model only considers combinations with positive values. Accordingly, these missing values are dropped below.   
        filter!(:Crsh_ht => x -> !ismissing(x), df_Crsh1)
        rename!(df_Crsh1,  :value => :Target_Crush)
        df_Crsh1.Crsh1= df_Crsh1.Target_Crush .* df_Crsh1.Crsh_ht


    #1.9) Exports - X
        df_X0 = DataFrame(region=String[], commodity=String[], X_ht=BigFloat[])
            for rk in rk_set_qsx_eq
                r=rk[1] 
                k=rk[2]
                value_X_ht = value(qs_Exp_ht[rk])  
                push!(df_X0, (r, k, value_X_ht))             
            end 
        df_X1    = outerjoin(df_X0, Target_X_df, on = [:region, :commodity])
        #NOTE: All region-commodity combinations for which the USDA reports that exports are zero, the model DOES NOT predict a result. It reports "missing".
        #      This is correct because the model only considers combinations with positive values. Accordingly, these missing values are dropped below.   
        filter!(:X_ht => x -> !ismissing(x), df_X1)
        rename!(df_X1,  :value => :Target_X)
        df_X1.X1 = df_X1.Target_X .* df_X1.X_ht


    #1.10) Ending Stocks
        df_ES0 = DataFrame(region=String[], commodity=String[], ES_ht=BigFloat[])
            for rk in rk_set_qdxss_eq
                r=rk[1] 
                k=rk[2]
                value_ES_ht = value(qd_XSS_ht[rk])  
                push!(df_ES0, (r, k, value_ES_ht))             
            end 
        df_ES1    = outerjoin(df_ES0, Target_ES_df, on = [:region, :commodity])
        #NOTE: All region-commodity combinations for which the USDA reports that ending stocks are zero, the model DOES NOT predict a result. It reports "missing".
        #      This is correct because the model only considers combinations with positive values. Accordingly, these missing values are dropped below.           
        filter!(:ES_ht => x -> !ismissing(x), df_ES1)
        rename!(df_ES1,  :value => :Target_ES)
        df_ES1.ES1 = df_ES1.Target_ES .* df_ES1.ES_ht
    

    #1.11) Loss
        df_Loss0 = DataFrame(region=String[], commodity=String[], Loss_ht=BigFloat[])
            for rk in rk_set_loss_eq
                r=rk[1] 
                k=rk[2]
                value_Loss_ht = value(LS_ht[rk])  
                push!(df_Loss0, (r, k, value_Loss_ht))             
            end 
        df_Loss1    = outerjoin(df_Loss0, Target_Loss_df, on = [:region, :commodity])
        #NOTE: All region-commodity combinations for which the USDA reports that losses are zero, the model DOES NOT predict a result. It reports "missing".
        #      This is correct because the model only considers combinations with positive values. Accordingly, these missing values are dropped below.           
        filter!(:Loss_ht => x -> !ismissing(x), df_Loss1)
        rename!(df_Loss1,  :value => :Target_Loss)
        df_Loss1.Loss1 = df_Loss1.Target_Loss .* df_Loss1.Loss_ht


    #1.12) Extraction Rate
        df_E0    = deepcopy(Target_E_df)
        filter!(:value => x -> !ismissing(x) && x != 0, df_E0)
        rename!(df_E0, :value => :Target_E)
        df_E1    =  combine(groupby(df_Crsh1, [:region]), :Crsh1 => sum)
        df_E1.commodity .= "SoyMeal"
        df_E2    =  combine(groupby(df_Crsh1, [:region]), :Crsh1 => sum)
        df_E2.commodity .= "SoyOil"
        df_E3    = vcat(df_E1, df_E2)   
        filter!(:Crsh1_sum => x -> !ismissing(x) && x != 0, df_E3)


    #1.13) Yields 
        df_Y0    = deepcopy(Target_Y_df)
        filter!(:value => x -> !ismissing(x) && x != 0, df_Y0)
        rename!(df_Y0, :value => :Target_Y)

#  --------------------------------------------------------------------------------------------------

#2) Simulation results

    df_Mkt = DataFrame(Iterators.product(region, commodity),    [:region, :commodity])
    df_Mkt = outerjoin(df_Mkt,  df_BS0,                    on = [:region, :commodity]) 
    df_Mkt = outerjoin(df_Mkt,  df_Q1,                     on = [:region, :commodity])
    df_Mkt = outerjoin(df_Mkt,  df_M1,                     on = [:region, :commodity])
    df_Mkt = outerjoin(df_Mkt,  df_DC1,                    on = [:region, :commodity]) 
    df_Mkt = outerjoin(df_Mkt,  df_DCFOOD1,                on = [:region, :commodity]) 
    df_Mkt = outerjoin(df_Mkt,  df_DCFEED1,                on = [:region, :commodity]) 
    df_Mkt = outerjoin(df_Mkt,  df_Crsh1,                  on = [:region, :commodity]) 
    df_Mkt = outerjoin(df_Mkt,  df_X1,                     on = [:region, :commodity])
    df_Mkt = outerjoin(df_Mkt,  df_ES1,                    on = [:region, :commodity])
    df_Mkt = outerjoin(df_Mkt,  df_Loss1,                  on = [:region, :commodity])
    df_Mkt = outerjoin(df_Mkt,  df_E0,                     on = [:region, :commodity])  
    df_Mkt = outerjoin(df_Mkt,  df_E1,                     on = [:region, :commodity])
    df_Mkt = outerjoin(df_Mkt,  df_Y0,                     on = [:region, :commodity])
    df_Mkt = outerjoin(df_Mkt,  df_A1,                     on = [:region, :commodity])


    #NOTE: All missing values are dropped. region and commodity are excluded because they are identifiers.
    df_Mkt = filter(row -> any(!ismissing, row[Not([:region, :commodity, :Crsh1_sum])]), df_Mkt)


    df_Mkt.nest = map(x -> x == "Beef"    || x == "Poultry" || x == "Pork" ? "Livestock" 
                         : x == "SoyMeal" || x == "SoyOil"                 ? "Secondary" 
                         : x == "Wheat"                                    ? "Brd_Cereals"  
                         : x == "Barley"                                   ? "Bly_Cereals"                                     
                         : x == "Corn"    || x == "Sorghum"                ? "Cereals"                                                                        
                         : x == "Cotton"                                   ? "Other" 
                         : x == "Soybean"                                  ? "Soy_Cereals" 
                         : x == "Rice"                                     ? "Rce_Cereals" 
                         : "",   df_Mkt.commodity)                

    df_Mkt.Y1                                 =  (df_Mkt.Q1 ./ df_Mkt.A1)                      
    df_Mkt.Y1[df_Mkt.commodity .== "Cotton"] .=  (df_Mkt.Q1[df_Mkt.commodity .== "Cotton"] .* 217.728111162486) ./ df_Mkt.A1[df_Mkt.commodity .== "Cotton"]
    # NOTE: 217.728111162486 corresponds to the conversion factor used by the USDA to convert one bale of cotton into kilograms. This value is implicitly 
    #       derived from the baseline projections and closely matches figures reported online (https://www.convertunits.com/from/bale/to/kg). The slight 
    #       difference is due to rounding at the decimal level.
                  

    df_Mkt.Y1[df_Mkt.commodity .== "Beef"]    .=  missing
    df_Mkt.Y1[df_Mkt.commodity .== "Pork"]    .=  missing
    df_Mkt.Y1[df_Mkt.commodity .== "Poultry"] .=  missing
    #NOTE: Livestock yields are not projected. Accordingly, the model reports them as missing.


    df_Mkt.E1  = fill(missing, nrow(df_Mkt))
    df_Mkt.E1  = convert(Vector{Union{Missing, Float64}}, df_Mkt.E1)
    df_Mkt.E1[df_Mkt.commodity .== "SoyOil"]  .= 100 .* (df_Mkt.Q1[df_Mkt.commodity .== "SoyOil"]  ./ df_Mkt.Crsh1_sum[df_Mkt.commodity .== "SoyOil"])
    df_Mkt.E1[df_Mkt.commodity .== "SoyMeal"] .= 100 .* (df_Mkt.Q1[df_Mkt.commodity .== "SoyMeal"] ./ df_Mkt.Crsh1_sum[df_Mkt.commodity .== "SoyMeal"])
                                          
#  --------------------------------------------------------------------------------------------------

#3) Exporting Simulation  Results - per year

    #3.1) Output file - Solutions

    #) long format solution
        df_output_sol = df_Mkt[:,[:region, :commodity, :nest, :Target_BS, :Q1, :M1, :DC1, :DCFOOD1, :DCFEED1, :X1, :ES1, :Loss1, :A1, :Crsh1, :Y1, :E1]]
        
        rename!(df_output_sol, :Target_BS        => :beg_stock)        
        rename!(df_output_sol, :Q1               => :production)
        rename!(df_output_sol, :M1               => :imports)
        rename!(df_output_sol, :DC1              => :tc)        
        rename!(df_output_sol, :DCFOOD1          => :food_cons)        
        rename!(df_output_sol, :DCFEED1          => :feed_cons)
        rename!(df_output_sol, :X1               => :exports)        
        rename!(df_output_sol, :ES1              => :end_stock)        
        rename!(df_output_sol, :Loss1            => :loss)        
        rename!(df_output_sol, :A1               => :area)
        rename!(df_output_sol, :Crsh1            => :crush)
        rename!(df_output_sol, :Y1               => :yields)
        rename!(df_output_sol, :E1               => :ext_rate)

        for col in [:beg_stock, :production, :imports, :tc, :food_cons, :feed_cons, :exports, :end_stock, :loss, :area, :crush, :yields, :ext_rate]
            df_output_sol[!, col] = convert(Vector{Union{Missing, Float64}}, df_output_sol[!, col])
        end
        #NOTE: this convert() is necessary to keep the "missing values" in the following reshape long needed to export the data

        solution_df = stack(df_output_sol, [:beg_stock, :production, :imports, :tc, :food_cons, :feed_cons, :exports, :end_stock, :loss, :area, :crush, :yields, :ext_rate], 
                                           [:region, :commodity, :nest])

        filter!(:value => x -> !ismissing(x) && x != 0, solution_df)
        #NOTE: This filter drops any missing values generated by reshaping the estimates. By construction, the model only considers positive values, 
        #      for which it may report zero in extreme cases but not missing values. For clarity, zeros are also removed.
        
        
    #) attribute
    #NOTE:  The baseline projections report consumption for rice, cotton, beef, pork, and poultry in aggregated form. Accordingly, any 
    #       disaggregated consumption generated during the data reshaping process for these commodities is dropped. For modeling purposes, 
    #       total consumption for these commodities is assumed to correspond entirely to food consumption.
    
        rename!(solution_df, :variable => :attribute)
        filter!(row -> !(row.attribute == "feed_cons" && row.commodity == "Rice"),    solution_df)
        filter!(row -> !(row.attribute == "feed_cons" && row.commodity == "Cotton"),  solution_df)
        filter!(row -> !(row.attribute == "feed_cons" && row.commodity == "Beef"),    solution_df)
        filter!(row -> !(row.attribute == "feed_cons" && row.commodity == "Pork"),    solution_df)
        filter!(row -> !(row.attribute == "feed_cons" && row.commodity == "Poultry"), solution_df)

        filter!(row -> !(row.attribute == "food_cons" && row.commodity == "Rice"),    solution_df)
        filter!(row -> !(row.attribute == "food_cons" && row.commodity == "Cotton"),  solution_df)
        filter!(row -> !(row.attribute == "food_cons" && row.commodity == "Beef"),    solution_df)
        filter!(row -> !(row.attribute == "food_cons" && row.commodity == "Pork"),    solution_df)
        filter!(row -> !(row.attribute == "food_cons" && row.commodity == "Poultry"), solution_df)

    #) year, input, attribute type, and commodity name    
        solution_df.year           = fill(i,         nrow(solution_df))
        solution_df.input          = fill("",        nrow(solution_df))
        solution_df.attribute_type = fill("RYNC",    nrow(solution_df))
        solution_df.commodity_name = solution_df.commodity

    #) unit    
        solution_df.unit                                        = fill("1,000 metric tones", nrow(solution_df)) 
        solution_df.unit[solution_df.commodity  .== "Cotton"]  .= "1,000 bales"
        solution_df.unit[solution_df.attribute  .== "area"]    .= "1,000 hectares"
        solution_df.unit[solution_df.attribute  .== "yields"]  .= "metric tons per hectare"     
        solution_df.unit[(solution_df.attribute .== "yields") .& (solution_df.commodity .== "Cotton")]  .= "kg per hectare"  
        solution_df.unit[solution_df.attribute  .== "ext_rate"]  .= "percentage" 

    #) attribute description
        solution_df.attribute_description  = map(x -> x == "beg_stock"     ? "Beginning Stocks" 
                                                    : x == "production"    ? "Production" 
                                                    : x == "imports"       ? "Imports"  
                                                    : x == "tc"            ? "Total Consumption"                                     
                                                    : x == "exports"       ? "Exports" 
                                                    : x == "end_stock"     ? "Ending Stocks" 
                                                    : x == "loss"          ? "Loss" 
                                                    : x == "area"          ? "Area" 
                                                    : x == "crush"         ? "Crushing" 
                                                    : x == "yields"        ? "Yields"                 
                                                    : x == "ext_rate"      ? "Extraction Rate" 
                                           : "",   solution_df.attribute)      

        solution_df.attribute_description[(solution_df.attribute .=="food_cons") .& (solution_df.commodity .=="Corn")]    .= "Food, seed, and industrial use"
        solution_df.attribute_description[(solution_df.attribute .=="food_cons") .& (solution_df.commodity .=="Sorghum")] .= "Food, seed, and industrial use"
        solution_df.attribute_description[(solution_df.attribute .=="food_cons") .& (solution_df.commodity .=="Wheat")]   .= "Food, seed, and industrial use"
        solution_df.attribute_description[(solution_df.attribute .=="food_cons") .& (solution_df.commodity .=="Barley")]  .= "Food, seed, and industrial use"
        solution_df.attribute_description[(solution_df.attribute .=="food_cons") .& (solution_df.commodity .=="Soybean")] .= "Food use"
        solution_df.attribute_description[(solution_df.attribute .=="food_cons") .& (solution_df.commodity .=="SoyOil")]  .= "Food use"
        solution_df.attribute_description[(solution_df.attribute .=="food_cons") .& (solution_df.commodity .=="SoyMeal")] .= "Food and other use"
       
        solution_df.attribute_description[(solution_df.attribute .=="feed_cons") .& (solution_df.commodity .=="Corn")]    .= "Feed use"
        solution_df.attribute_description[(solution_df.attribute .=="feed_cons") .& (solution_df.commodity .=="Sorghum")] .= "Feed use"
        solution_df.attribute_description[(solution_df.attribute .=="feed_cons") .& (solution_df.commodity .=="Wheat")]   .= "Feed use"
        solution_df.attribute_description[(solution_df.attribute .=="feed_cons") .& (solution_df.commodity .=="Barley")]  .= "Feed use"
        solution_df.attribute_description[(solution_df.attribute .=="feed_cons") .& (solution_df.commodity .=="Soybean")] .= "Feed, seed, and waste"
        solution_df.attribute_description[(solution_df.attribute .=="feed_cons") .& (solution_df.commodity .=="SoyOil")]  .= "Industry, feed and other use"
        solution_df.attribute_description[(solution_df.attribute .=="feed_cons") .& (solution_df.commodity .=="SoyMeal")] .= "Feed use"        

    #) region name 
        solution_df.region_name            = map(x -> x == "ARG"  ?  "Argentina" 
                                                    : x == "AUS"  ?  "Australia"
                                                    : x == "BGD"  ?  "Bangladesh"
                                                    : x == "BRA"  ?  "Brazil"
                                                    : x == "BUR"  ?  "Burma"
                                                    : x == "CAC"  ?  "Central America & Caribbean"
                                                    : x == "CAN"  ?  "Canada"
                                                    : x == "CHN"  ?  "China"
                                                    : x == "ECO"  ?  "West African Community=Ecowas (minus Nigeria)"
                                                    : x == "EGY"  ?  "Egypt"
                                                    : x == "EUR"  ?  "European Union"
                                                    : x == "HKG"  ?  "Hong Kong"
                                                    : x == "IDN"  ?  "Indonesia"
                                                    : x == "IND"  ?  "India"
                                                    : x == "IRN"  ?  "Iran"
                                                    : x == "IRQ"  ?  "Iraq"
                                                    : x == "JPN"  ?  "Japan"
                                                    : x == "KHM"  ?  "Cambodia"
                                                    : x == "KOR"  ?  "South Korea"
                                                    : x == "MAR"  ?  "Morocco"
                                                    : x == "MEX"  ?  "Mexico"
                                                    : x == "MYS"  ?  "Malaysia"
                                                    : x == "NGA"  ?  "Nigeria"
                                                    : x == "NZL"  ?  "New Zealand"
                                                    : x == "OAO"  ?  "Other Asia & Oceania"
                                                    : x == "OEU"  ?  "Other Europe"
                                                    : x == "OFS"  ?  "Other Former Soviet Union, 10 Countries"
                                                    : x == "OME"  ?  "Other Middle East"
                                                    : x == "ONA"  ?  "Other North Africa"
                                                    : x == "OSA"  ?  "Other South America"
                                                    : x == "OSS"  ?  "Other Sub-Saharan Africa"
                                                    : x == "PAK"  ?  "Pakistan"
                                                    : x == "PHL"  ?  "Philippines"
                                                    : x == "RUS"  ?  "Russia"
                                                    : x == "SAU"  ?  "Saudi Arabia"
                                                    : x == "THA"  ?  "Thailand"
                                                    : x == "TUR"  ?  "Turkey"
                                                    : x == "TWN"  ?  "Taiwan"
                                                    : x == "UKR"  ?  "Ukraine"
                                                    : x == "USA"  ?  "United States"
                                                    : x == "VNM"  ?  "Vietnam"
                                                    : x == "ZAF"  ?  "Republic of South Africa"
                                           : "",   solution_df.region)  
               
    #) nest name
        solution_df.nest_name              = map(x -> x == "Bly_Cereals"   ?  "Barley_Cereals" 
                                                    : x == "Brd_Cereals"   ?  "Bread Cereals"
                                                    : x == "Cereals"       ?  "Cereals"
                                                    : x == "Livestock"     ?  "Livestock"
                                                    : x == "Other"         ?  "Other"
                                                    : x == "Rce_Cereals"   ?  "Rice Cereals"
                                                    : x == "Secondary"     ?  "Soy related Secondary"
                                                    : x == "Soy_Cereals"   ?  "Soybean Cereals"                                                    
                                            : "",   solution_df.nest)      

        data_solution = solution_df[:, [:region, :year, :nest, :commodity, :input, :attribute, :value, :unit, :attribute_type, :attribute_description, :region_name, 
                                        :nest_name, :commodity_name]]
        CSV.write("Output_$i/data_solution.csv", data_solution)


    #3.2) Output file -  Targets
        CSV.write("Output_$i/data_targets.csv", info_targets)


    #3.3) Output file - Parameters
        tab_exog_A             = combine(groupby(info_exogenous, :attribute), nrow => :Count)
        data_parameters_calb_A = info_exogenous[(info_exogenous.attribute .== "sigma_t") .|
                                                (info_exogenous.attribute .== "sigma_u") .|
                                                (info_exogenous.attribute .== "sigma_n") .|
                                                (info_exogenous.attribute .== "sigma_a") .|
                                                (info_exogenous.attribute .== "sigma_i") .|
                                                (info_exogenous.attribute .== "phi_i")   .|
                                                (info_exogenous.attribute .== "phi_f")   .|
                                                (info_exogenous.attribute .== "omega_q") .|
                                                (info_exogenous.attribute .== "omega_c") .|
                                                (info_exogenous.attribute .== "epsilon_l") .|
                                                (info_exogenous.attribute .== "epsilon_q") ,:]

        tab_exog_B             = combine(groupby(info_parameters, :attribute), nrow => :Count)
        data_parameters_calb_B = info_parameters

        data_parameters_calb   = vcat(data_parameters_calb_A, data_parameters_calb_B)

        CSV.write("Output_$i/data_params_calibrated.csv", data_parameters_calb)


    #3.4) Output file - Exogenous data
        tab_exog_A
        data_exogenous_sol = info_exogenous[(info_exogenous.attribute .== "International Price")         .|
                                            (info_exogenous.attribute .== "GDP per capita")              .|
                                            (info_exogenous.attribute .== "Population")                  .|
                                            (info_exogenous.attribute .== "Price of No Land Input")      .|
                                            (info_exogenous.attribute .== "Price of No AG")              .|
                                            (info_exogenous.attribute .== "P_NO_FEED")                   .|
                                            (info_exogenous.attribute .== "inv_liv")                     .|
                                            (info_exogenous.attribute .== "slt_liv")                     .|
                                            (info_exogenous.attribute .== "Ag Expenditure Share")        .|
                                            (info_exogenous.attribute .== "NTM for exporting a product") .|
                                            (info_exogenous.attribute .== "NTM for importing a product") .|
                                            (info_exogenous.attribute .== "Export tax")                  .|
                                            (info_exogenous.attribute .== "Import tariff")               .|
                                            (info_exogenous.attribute .== "Land Unavailability ")        .|
                                            (info_exogenous.attribute .== "TFP Productivity Value Added") .|   
                                            (info_exogenous.attribute .== "TFP Productivity Intermediates") .|   
                                            (info_exogenous.attribute .== "TFP Productivity Feed Use")   .|                                                                                                       
                                            (info_exogenous.attribute .== "Land Productivity") ,:]

        CSV.write("Output_$i/data_exogenous.csv", data_exogenous_sol)


    #3.5) Output file - Shocks data
        CSV.write("Output_$i/data_shocks.csv", info_Shocks)


    #3.6) Output file - METADATA
        METADATA = DataFrame(field = ["Author",    "Description",       "Comments", "Model calibration", "Scenario simulation"],
                             value = ["BSAT team", "Baseline scenario", "None"    ,  now()             ,  now()])
        CSV.write("Output_$i/METADATA.csv", METADATA)

#---------------- 
end
