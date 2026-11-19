# Imputation of Missing AVE of NTM

This document describes the regression model used to impute missing Ad Valorem Equivalent (AVE) values for Non-Tariff Measures (NTMs) at the country-product level.

## Model Specification

We estimate the following regression model:

$$ave^{NTM}_{ck} = \beta_1 ave^{Tariff}_{ck} + \beta_2 ave^{AgTariff}_c + \beta_3 \log(GDPpc_c) + \beta_4 \log(TotalAgImport_c) + \delta_{rk} + \epsilon_{ck}$$



Where:
- $c$: country
- $k$: product ID (including 12 baseline agricultural commodities and other HS 6-digit code products)
- $r$: region
- $\delta_{rk}$: region-product cell fixed effect, which absorbs the separate region and product main effects
- $ave^{Tariff}_{ck}$: AVE of tariff for country $c$ and product $k$
- $ave^{AgTariff}_c$: country-level average tariff on agricultural products
- $GDPpc_c$: GDP per capita for country $c$
- $TotalAgImport_c$: total agricultural imports of country $c$
- $\epsilon_{ck}$: error term. 

## Purpose

This model is used to impute missing values of $ave^{NTM}_{ck}$, leveraging observed tariff levels, country-level trade and economic indicators, and fixed effects to capture regional and product-specific variation.

## Notes

- The source AVE is constructed as the row sum of `ave1C` and `ave2C` with missing components treated as zero. If both components are missing, the resulting observed AVE is therefore zero.
- The country-product grid is completed before imputation. A prediction is used only when a country-product observation is absent; an observed zero is retained as observed rather than imputed.
- The imputation is limited to observations where the necessary right-hand-side variables or fixed effects are available.
- Negative predictions are truncated to zero before aggregation. Predictions with missing right-hand-side variables or fixed effects remain missing and may subsequently be covered by the documented crop-average or regional fallback rules in the code.
