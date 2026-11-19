# BSAT data-processing pipeline

R pipeline that turns the public raw data in `data/raw/` into the four standard model input files in `data/processed/` and the baseline input package in `data/packages/`.

## Run

From the repository root: `scripts/run_r_pipeline_unix.sh` or `scripts\run_r_pipeline_windows.bat`.
Or, from this folder, `Rscript main.R`. The data root defaults to `<repo>/data`; set `BSAT_DATA_DIR` to use another location.

`main.R` sources the scripts in `R/` in numeric order:

| Script | Produces |
|---|---|
| `00` load packages, `01` coverage check | `interim/region_commodity_coverage.csv` |
| `10` read the USDA baseline workbook, `11` feed-use decomposition, `12` targets | `processed/data_targets.csv` |
| `20` expenditure shares and prices, `21` land cost shares, `22` tariffs and export taxes, `23` non-tariff measures, `24` exogenous data | `processed/data_exogenous.csv` |
| `30` neutral shocks | `processed/data_shocks.csv` |
| `40` initial parameters | `processed/data_params_init.csv` |
| `50` target harmonization | `processed/data_targets.csv` (overwritten), `interim/harmonization_log.csv` |
| `60` package | `packages/baseline_<year>_Input.zip` |

Scripts `22` and `23` read raw trade files that are not distributed with the repository, two for size and the others under UNCTAD TRAINS and WTO terms (see `scripts/fetch_large_raw_data.sh`). Without them, `main.R` skips both scripts and reuses their derived files shipped in `interim/`. Script `25` is a diagnostic run by hand after `23`. 

Every script carries a header with its purpose, inputs, outputs and dependencies. The full guide is `doc/pipeline.qmd`; the procedure for a new data vintage is `doc/updating-raw-data.qmd`; the file format is `doc/data/data_specification.md`; the sources are `doc/data/data_source.md`.

## Requirements

R 4.4 or later with `dplyr`, `tidyr`, `stringr`, `readr`, `readxl`, `openxlsx`, `data.table`, `lfe`, `ggplot2`, `zip` (all installed, with R 4.5, by the bootstrap scripts from `setup/environment.yml`).
