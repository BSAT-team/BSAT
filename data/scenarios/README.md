# Scenarios from an edited shocks CSV

This folder holds the shocks template and the shipped scenario definitions for the CSV route to a model run: edit a CSV in a spreadsheet, run one command, get the output package.

```
scripts/run_scenario_unix.sh my_case.csv                    # macOS, Linux, container
scripts\run_scenario_windows.bat my_case.csv                # Windows
```

The command builds `output/my_case_Input.zip` from the baseline package, prints the rows that differ from the baseline, runs the model (about two minutes), and writes `output/my_case_Output.zip`. Optional second and third arguments give the output path and the scenario description shown in the dashboard. To check a CSV without running the model, call the Julia entry point with `--build-only`:

```
julia --project=code/model code/model/run_scenario.jl --shocks my_case.csv --build-only
```

## Files

| File | Content |
|---|---|
| `shocks_template.csv` | The baseline `data_shocks.csv`: every region, commodity, year and attribute the model knows, all values 0 (28,980 rows). Copy it, edit the `value` column, save. |
| `case1_land_supply_ukraine.csv` | Case 1: Ukraine land supply 20 percent lower in 2026 |
| `case2_export_tax_india.csv` | Case 2: India rice and wheat export tax +50 percentage points in 2026 |
| `case3a_tfp_soybean_china.csv` | Case 3a: China soybean value-added TFP rising 1 to 9 percent over 2026 to 2034 (2025, the realized base year, unshocked) |
| `case3b_tfp_soybean_china_half.csv` | Case 3b: same ramp at half strength, 0.5 to 4.5 percent |
| `case4_land_productivity_usa.csv` | Case 4: US corn and soybean land productivity 10 percent lower in 2026 |
| `example_china_soybean_tariff.csv` | Walkthrough example: China soybean import tariff +10 percentage points from 2026 |

The six case files list only the rows they change. Each one rebuilds the corresponding package in `data/packages/` exactly (the model test suite checks this).

## Writing a scenario CSV

Two forms are accepted, and can be mixed freely:

- **A full copy of the template** with some values edited. Filter in the spreadsheet by `attribute`, `region`, `commodity` and `year`, type the values, save as CSV.
- **A partial file** holding only the rows to change, with the five columns below. Rows absent from the file keep the baseline value (0).

Rows are matched on `region`, `year`, `commodity` and `attribute`. Only these five columns are read; every other column of the template (`nest`, `unit`, the name columns, ...) is ignored and may be deleted or kept. Header names are matched regardless of case and surrounding spaces, and so are region and commodity codes.

| Column | Content |
|---|---|
| `region` | ISO-3 style region code, see the list below |
| `year` | 2025 to 2034 (`2026.0`, as some spreadsheets write it, is accepted) |
| `commodity` | commodity code, see the list below; blank for the two region-level attributes |
| `attribute` | one of the ten attribute names, spelled exactly as below (two contain spaces) |
| `value` | the shock as a decimal number; 0 is neutral |

A row that cannot be applied is reported in a warning with its line number and skipped, and the run continues with the rows that could: unknown attribute, region or commodity; a commodity on a region-level attribute or none on a commodity-level one; a year outside 2025 to 2034; a blank or non-numeric value; a region and commodity pair the model does not have for that attribute (for example `shock_land_prod` for `Beef`). If the same key appears twice, the last row wins and a warning says so. If no row can be applied the command stops. If every applied value is 0 the command warns that the scenario equals the baseline and runs it anyway.

The shocks file written into the package is regenerated from the template, so the spreadsheet's number formats, line endings and byte-order mark never reach the model. Saving from Excel as "CSV UTF-8 (comma delimited)" or plain "CSV (comma delimited)" both work. Keep the decimal separator a point: on a system with a comma decimal separator, Excel writes `0,1` and separates columns with semicolons, which the command does not read; set the separators to point and comma in the spreadsheet's options, or type the values in a text editor.

## The ten shock attributes

Every value is a decimal added to the baseline level of the variable in the year of the row, except the expenditure share, which is scaled. The neutral value is 0 for all of them. Which commodities an attribute takes is fixed by the model; the template lists exactly the rows that exist.

| Attribute | Level | Commodities | Meaning of the value |
|---|---|---|---|
| `shock_import_tariff` | region, year, commodity | all twelve | ad valorem import tariff, added: 0.10 = +10 percentage points |
| `shock_export_tax` | region, year, commodity | all twelve | ad valorem export tax, added |
| `shock_nontariff_import` | region, year, commodity | all twelve | ad valorem equivalent of import non-tariff measures, added |
| `shock_nontax_export` | region, year, commodity | all twelve | ad valorem equivalent of export non-tax measures, added |
| `shock_land_prod` | region, year, commodity | the seven crops | land productivity shifter: -0.10 = 10 percent lower yield per hectare |
| `shock TFP Productivity Value Added` | region, year, commodity | the seven crops | total factor productivity in value added, decimal change |
| `shock TFP Productivity Intermediates` | region, year, commodity | SoyMeal, SoyOil | total factor productivity in intermediate use (soybean crushing), decimal change |
| `shock_TFP_Productivity_Feed_Use_livestock` | region, year, commodity | Beef, Pork, Poultry | total factor productivity in feed use of livestock, decimal change |
| `shock_land_supply` | region, year | none (leave blank) | land supply availability: -0.10 = 10 percent less land |
| `shock_ag_expenditure_share` | region, year | none (leave blank) | agricultural expenditure share, proportional: 0.05 = 5 percent higher share |

The model reads the shocks of the year it is solving; years do not feed into each other, so a shock placed in 2026 alone changes 2026 alone, and a persistent shock needs a row for every year.

## Commodity codes

The seven crops are `Barley`, `Corn`, `Cotton`, `Rice`, `Sorghum`, `Soybean`, `Wheat`; the two soybean products `SoyMeal`, `SoyOil`; the three livestock products `Beef`, `Pork`, `Poultry`.

## Region codes

| Code | Region | Code | Region |
|---|---|---|---|
| `ARG` | Argentina | `MYS` | Malaysia |
| `AUS` | Australia | `NGA` | Nigeria |
| `BGD` | Bangladesh | `NZL` | New Zealand |
| `BRA` | Brazil | `OAO` | Other Asia and Oceania |
| `BUR` | Burma | `OEU` | Other Europe |
| `CAC` | Central America and Caribbean | `OFS` | Other Former Soviet Union |
| `CAN` | Canada | `OME` | Other Middle East |
| `CHN` | China | `ONA` | Other North Africa |
| `ECO` | West African Community (ECOWAS minus Nigeria) | `OSA` | Other South America |
| `EGY` | Egypt | `OSS` | Other Sub-Saharan Africa |
| `EUR` | European Union | `PAK` | Pakistan |
| `HKG` | Hong Kong | `PHL` | Philippines |
| `IDN` | Indonesia | `RUS` | Russia |
| `IND` | India | `SAU` | Saudi Arabia |
| `IRN` | Iran | `THA` | Thailand |
| `IRQ` | Iraq | `TUR` | Turkey |
| `JPN` | Japan | `TWN` | Taiwan |
| `KHM` | Cambodia | `UKR` | Ukraine |
| `KOR` | South Korea | `USA` | United States |
| `MAR` | Morocco | `VNM` | Vietnam |
| `MEX` | Mexico | `ZAF` | South Africa |

The full names are also in the `region_name` column of the template.
