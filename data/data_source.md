# Data Source Reference — 2025–2034 version

_Date created: 2026-06-19_

_Last modified: 2026-09-04_

Sources of the raw data files in `data/raw/` for the **2025–2034** version (USDA 2025 baseline).
Files are grouped by role in the pipeline, mirroring the README's *Overview of input data*; every file
listed is present in `data/raw/` except the five trade-barrier files marked *not distributed*, whose derived
products are shipped in `data/interim/` (see [Raw data sources](../data-sources.qmd)). For **which script reads each file**, see the pipeline
table in the [README](../README.md). Source URLs are defined once at the bottom and reused as named links.

---

## 1. USDA baseline

- **2025 International Long-Term Projections to 2034.xlsx** — USDA 10-year international baseline (area, yield, production, consumption, trade, stocks, feed use). [USDA International Baseline Data][usda-baseline]
- **region_commodity_list_2025.xlsx** — region × commodity coverage for the 2025 baseline (project-maintained).
- **baseline_units.csv** — unit of each baseline attribute (project-maintained).

## 2. Macro & population

- **Current_GDP_WB_2025.xls** — GDP, current US$. [World Bank — GDP (current US$)][wb-gdp-cd]
- **population_WB_2025.xls** — total population. [World Bank — Population][wb-pop]
- **Current_GDP_IMF_WEO_2025.csv**, **population_IMF_WEO_2025.csv** — GDP (current prices) and population from the IMF WEO; this pipeline uses them only to supplement Taiwan, which is absent from the World Bank series. [IMF WEO][imf-weo]
- **Global GDP Shares and GDP Growth Assumptions to 2035.xlsx** — GDP shares and growth assumptions underlying the USDA baseline. [USDA Agricultural Projections to 2035][usda-proj]
- **current_GDP_2014_WB.csv**, **current_GDPpc_2014_WB.csv** — 2014 GDP and GDP per capita, current US$. [World Bank WDI][wb-wdi]
- **current_GDP_IMF.xls**, **current_GDPpc_IMF.xls** — 2014 GDP / GDP per capita from the IMF WEO; the NTM step uses them only for Taiwan, which is absent from the World Bank series. [IMF WEO][imf-weo]

## 3. International prices & CPI

- **2026-06-19 IMF Commodity Prices external-data.xlsx** — IMF Primary Commodity Prices, monthly (the nine non-meat commodities). [IMF Primary Commodity Prices][imf-commodity]
- **2026-06-19 International Prices FAO Meat.xlsx** — FAO GIEWS FPMA international meat export prices (Beef, Pork, Poultry). [FAO GIEWS FPMA][fao-fpma]
- **2026-06-24 CPI_US.xlsx** — U.S. CPI-U (all items, U.S. city average, annual average), rebased to 2017 = 1. [BLS CPI][bls-cpi] · equivalent series [FRED CPIAUCNS][fred-cpi]

## 4. Trade barriers

- **tariff_ave_WITS_2023.csv** — 2023 import-tariff AVEs. *Not distributed (UNCTAD TRAINS terms); obtain from source:* WITS Advanced Query, Tariff and Trade Analysis (TRAINS), all reporters, all partners, all HS6 products, year 2023, AVE of applied tariff, CSV export. Derived products `tariff_ave_region.csv` and `export_taxes_comm_reg.csv` are shipped in `data/interim/`. [WITS][wits]
- **tariff_ave_2014_WITS.csv** — 2014 tariff AVEs. *Not distributed (size, >100 MB); obtain from source:* same WITS query with year 2014. [WITS][wits]
- **ag_hs_products.csv** — agricultural-product HS-code list. *Not distributed (UNCTAD TRAINS terms); obtain from source:* WITS product group `WTO_HS_Aggri` exported as CSV with a `Product` column of HS6 codes. [WITS][wits]
- **country_code_WITS.xlsx** — WITS reporter/partner ↔ ISO-3 codes (distributed lookup). [WITS][wits]
- **ag_tariff_USA_2014.xls** — U.S. applied-MFN HS6 tariff schedule (2014); source of the baseline commodity ↔ HS6 mapping. *Not distributed (WTO terms); obtain from source:* WTO Tariff and Trade Data export of the United States applied MFN schedule for 2014, sheet `Applied_MFN`, HS6 codes in column E from row 6. The derived mapping `commodity_hs6_mapping.csv` (67 HS6 codes) is shipped in `data/interim/`. [WTO Tariff & Trade Data][wto-ttd]
- **ave_hs_importer.csv** — ad-valorem equivalents of non-tariff measures by importer × HS code. [World Bank NTM AVEs][wb-ntm]
- **BACI_HS92_Y2014_V202401b.csv** — HS6 bilateral trade flows, 2014. *Not distributed (size, >100 MB); obtain from source:* `scripts/fetch_large_raw_data.sh --download` downloads the CEPII archive and extracts the 2014 file. The NTM outputs `NTM_IMP_ave_region.csv` and `NTM_EXP_ave_region.csv` derived from this file and the two 2014 WITS files are shipped in `data/interim/`. [CEPII BACI][cepii-baci]
- **country_codes_V202401b.csv** — BACI numeric country codes ↔ ISO-3. [CEPII BACI][cepii-baci]
- **country_region_WB.xlsx** — World Bank geographic regions / lending groups. [World Bank country & lending groups][wb-groups]

## 5. Land, cost & livestock

- **AgTFPInternational2023.xlsx** — international agricultural land cost shares (TFP accounts). [USDA International Agricultural Productivity][usda-tfp]
- **variable_costs_2025/** — USDA per-acre variable costs to 2035 (Feed Grains, Rice, Soybeans and products, Upland Cotton, Wheat). [USDA Agricultural Projections to 2035][usda-proj]
- **FAOSTAT_each_livestock_value_constant_IntlD.csv**, **FAOSTAT_total_livestock_value_constant_IntlD.csv** — gross production value by livestock item and total (constant international dollars). [FAOSTAT — QV][faostat-qv]
- **FAOSTAT_Livestock_Inventory_2024.csv**, **FAOSTAT_Slaughtered Livestock_2024.csv** — live-animal inventories and animals slaughtered. [FAOSTAT — QCL][faostat-qcl]

## 6. Identifiers & parameters

- **mapping.csv** — country ↔ 42-region identifiers and A/B/C aggregation groups (project-maintained).
- **exogenous_data.csv** — calibrated elasticities and other per-region exogenous parameters (project-maintained).

---

<!-- Source URLs (reference-style links; each defined once — edit here to update every use above). -->

[usda-baseline]: https://www.ers.usda.gov/data-products/international-baseline-data
[usda-proj]: https://www.ers.usda.gov/publications/pub-details?pubid=113816
[usda-tfp]: https://www.ers.usda.gov/data-products/international-agricultural-productivity
[wb-wdi]: https://databank.worldbank.org/source/world-development-indicators
[wb-gdp-cd]: https://data.worldbank.org/indicator/NY.GDP.MKTP.CD
[wb-pop]: https://data.worldbank.org/indicator/SP.POP.TOTL
[wb-groups]: https://datahelpdesk.worldbank.org/knowledgebase/articles/906519-world-bank-country-and-lending-groups
[imf-weo]: https://www.imf.org/en/Publications/SPROLLs/world-economic-outlook-databases#sort=%40imfdate%20descending
[imf-commodity]: https://www.imf.org/en/research/commodity-prices
[fao-fpma]: https://fpma.fao.org/giews/fpmat4/global/#/dashboard/tool/international
[bls-cpi]: https://www.bls.gov/cpi/
[fred-cpi]: https://fred.stlouisfed.org/series/CPIAUCNS
[wits]: https://wits.worldbank.org/
[wto-ttd]: https://ttd.wto.org/en
[cepii-baci]: https://www.cepii.fr/CEPII/en/bdd_modele/bdd_modele_item.asp?id=37
[wb-ntm]: https://datacatalog.worldbank.org/search/dataset/0040437
[faostat-qv]: https://www.fao.org/faostat/en/#data/QV
[faostat-qcl]: https://www.fao.org/faostat/en/#data/QCL
