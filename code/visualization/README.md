---
title: BSAT
emoji: 👁
colorFrom: purple
colorTo: indigo
sdk: streamlit
sdk_version: 1.44.1
python_version: "3.10"
app_file: app.py
pinned: false
---

# BSAT Scenario Dashboard

An interactive Streamlit dashboard for BSAT (Baseline Scenario Analysis Tool). Upload one or two model output packages and compare the scenario solution with the baseline across regions, commodities, attributes and years.

## What the dashboard does

For each uploaded package the app reads the baseline (targets) and the scenario solution, joins them on region, commodity, year and attribute, and computes the ratio `solution / baseline` for every observation (rounded to four decimals). A neutral run (no active shocks) therefore shows ratios of 1 everywhere. With two packages the second scenario is compared against the baseline of the first; if the two baselines differ, a warning says so.

Views, in the order they appear on the page:

- **Metadata**: the `METADATA.csv` of each package (author, description, model version, years requested and solved).
- **Time series: region, commodity, variable** (line chart, open by default): baseline and scenario values over time for one region, commodity and variable, labelled with the unit of the series.
- **Regional changes: commodity, year, variable** (bar chart): percent change by region for a commodity, year and variable, side by side for two scenarios; click the legend to toggle a scenario. Every region is labelled, names truncated to 20 characters (the tooltip has the full name).
- **Heatmap of changes: year, variable**: percent change by region and commodity for a year and variable; with two scenarios a radio button picks the one shown. The color scale is symmetric around zero and spans the largest absolute change of either scenario in the view (between 1 and 100 percent; larger changes take the end colors), so colors are comparable across the two. Cells that round to 0.0 percent are white; combinations without data are light gray.
- **Top Regional Changes: commodity, year, variable**: the regions with the largest absolute percent change for a commodity, year, variable and scenario. Increases are red and decreases blue, the end colors of the heatmap scale, so small changes stay visible.
- **Table: Baseline Data**: the raw baseline file of either package with column filters.
- **Table: Scenario Variables**: the `data_shocks.csv` of each package, either all rows or only changed values (value different from 0; all shock attributes are decimals added to the baseline level, so 0 is the neutral value).

Region, commodity and variable dropdowns show the display names carried in the data (`region_name`, `commodity_name`, `attribute_description`) and list only what is present. The years offered are those for which the solution has values, and each year dropdown opens on the second of them, the first year in which a shock can act, since the first year reproduces the observed data.

## Expected package

A package is the `Output.zip` written by the BSAT model (`scripts/run_model_*`). The dashboard reads these members, at the archive root or inside a folder:

| File | Role | Required |
| --- | --- | --- |
| `data_targets_adjusted.csv` | baseline (targets after harmonisation) | yes |
| `data_solution.csv` | scenario solution | yes |
| `data_shocks.csv` | policy shock inputs | optional |
| `METADATA.csv` | `field,value` pairs describing the run | optional |

`data_params_calibrated.csv`, `data_exogenous.csv` and `SCENARIO_SOLVER_LOG.txt` are ignored. Baseline and solution rows share the 13-column format `region, year, nest, commodity, input, attribute, value, unit, attribute_type, attribute_description, region_name, nest_name, commodity_name`. Solution attributes are lowercase codes (`production`, `imports`, `beg_stock`, ...) that the app maps to the display names used by the baseline (`Production`, `Imports`, `Beginning Stocks`, ...). Input-level baseline rows (attribute type `RYNCI`) are not used.

Packages from older model versions that contain `data_targets.csv` instead of `data_targets_adjusted.csv` are accepted as a fallback; the app shows a note when it uses that file. Uploads are limited to 20 MB per package.

## Hosted use

The dashboard is hosted on Hugging Face Spaces, where it runs with the Streamlit version declared in the front matter of this file. Uploaded files are held in memory for the session and are not stored.

Space URL: https://huggingface.co/spaces/bsat-team/BSAT_Viz

## Running locally

### With the repository scripts

After `scripts/bootstrap_unix.sh` or `scripts\bootstrap_windows.bat` has created the local environment, start the dashboard from the repository root:

```bash
scripts/run_dashboard_unix.sh
```

```bat
scripts\run_dashboard_windows.bat
```

Open `http://localhost:8501` in a browser.

### With pip

From this folder (`code/visualization`), with Python 3.10 to 3.12:

```bash
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt
streamlit run app.py
```

`requirements.txt` pins every package, direct and transitive, to the set the hosted copy runs: Streamlit 1.44.1, pandas 2.2.3, numpy 1.26.4, pyarrow 19.0.1, altair 5.5.0. The full pin matters: an unpinned pyarrow once moved to a release that requires NumPy 2 and broke the hosted dashboard. The app also runs on newer stacks (tested with Streamlit 1.63, pandas 3.0, numpy 2.4, altair 6.2, as in the conda environment `setup/environment-dashboard.yml`).

## Code layout

- `app.py`: Streamlit entry point (layout, widgets, charts).
- `bsat_dashboard.py`: pure data functions (package parsing, merging, shock filtering, region labels, chart selections). No Streamlit dependency, so it can be tested directly.
- `tests/test_loaders.py`: tests for the loaders on real and synthetic packages. Run `pytest tests/` from this folder, or `python tests/test_loaders.py` when pytest is not installed.
- `.streamlit/config.toml`: server settings (upload size limit).
