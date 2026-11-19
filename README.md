# BSAT: Baseline Scenario Analysis Tool

BSAT simulates how the USDA 10-year international agricultural baseline responds to policy and productivity shocks. It is a calibrated, multi-region partial-equilibrium model of 12 commodities (barley, beef, corn, cotton, pork, poultry, rice, sorghum, soybeans, soybean meal, soybean oil, wheat) in 42 countries and regions. With no shocks it reproduces the baseline projections exactly, year by year; with shocks it reports the new production, consumption, trade, stock, and yield paths against that baseline.

The package has three parts, each usable on its own:

| Part | What it does | Language |
|---|---|---|
| `code/processing/` | Builds the model inputs from public raw data (USDA baseline, World Bank, IMF, FAOSTAT, WITS, CEPII) | R |
| `code/model/` | Runs the model on an input package and writes an output package | Julia (JuMP, PATH solver) |
| `code/visualization/` | Compares up to two output packages in the browser | Python (Streamlit) |

Data flow: raw files in `data/raw/` go through the pipeline into four standard CSV files (`data/processed/`) and a baseline input package (`data/packages/`). A scenario is a copy of that package with edited shocks. The model turns an input package into an output package, which the dashboard reads.

## Quick start

1. Install one of the three ways: a ready-made container (GitHub Codespaces or Docker), or a portable local install on macOS, Linux, or Windows that needs no administrator rights (`scripts/bootstrap_unix.sh` or `scripts\bootstrap_windows.bat`; add `--no-dashboard` to skip the optional Python environment for the local dashboard). See `doc/installation/`.
2. Paste a free PATH solver license into `code/model/path_license.txt` (instructions in `path_license.txt.example`).
3. Run the baseline:

```
scripts/run_model_unix.sh            # or scripts\run_model_windows.bat
```

This writes `output/baseline_Output.zip` in about two minutes.

4. Define a scenario and run it. Write a CSV listing the rows of `data_shocks.csv` to change (or edit a copy of `data/scenarios/shocks_template.csv` in a spreadsheet), then one command builds the package, runs the model, and writes the output:

```
scripts/run_scenario_unix.sh data/scenarios/example_china_soybean_tariff.csv output/my_case_Output.zip "China soybean tariff +10 pp"
```

   The same shock from the command line, without a CSV:

```
julia --project=code/model code/model/make_shock.jl --template data/packages/baseline_2025_Input.zip \
      --inputpkg output/my_case_Input.zip --shock shock_import_tariff --value 0.10 \
      --regions CHN --commodities Soybean --years 2026:2034 --description "China soybean tariff +10 pp"
scripts/run_model_unix.sh output/my_case_Input.zip output/my_case_Output.zip
```

5. Open the hosted dashboard at https://huggingface.co/spaces/bsat-team/BSAT_Viz and upload `output/my_case_Output.zip`; the package carries the baseline it was solved against, so nothing else is needed, and a second package can be uploaded to compare two shocks. `scripts/run_dashboard_unix.sh` runs the dashboard server on your own computer and is only for local installs.

The full walkthrough, including the stylized cases, is in `doc/walkthrough.qmd`; the rendered documentation site is published from `doc/`.

## Shocks

Ten shock attributes can be set per region, commodity, and year: import tariffs, export taxes, non-tariff import and export measures, land productivity, total factor productivity in value added, in intermediate use, and in livestock feed use, land supply, and the agricultural expenditure share. Values are decimals added to the baseline level (the expenditure share is scaled); zero means no shock. `make_shock.jl --list` prints the table; `data/scenarios/README.md` documents the attributes, units and codes for editing the shocks file in a spreadsheet, and holds the four stylized cases of the working paper as small CSVs.

## Rebuilding the inputs

`scripts/run_r_pipeline_unix.sh` rebuilds the processed files and the baseline package from `data/raw/`. Five raw trade files are not distributed with the repository, two for size and three because their sources' terms do not allow it (`scripts/fetch_large_raw_data.sh` explains how to obtain them); without them the pipeline reuses the derived files shipped in `data/interim/` for the tariff and non-tariff-measure steps. How to bring in a new data vintage is described in `doc/updating-raw-data.qmd`.

## Verifying an installation

```
julia --project=code/model code/model/test/runtests.jl       # model: byte-level regression, about 4 minutes
python code/visualization/tests/test_loaders.py               # dashboard loaders
```

## Documentation

- `doc/`: installation, walkthrough, data format, data sources, pipeline, model, dashboard, function reference, contract deliverables.
- `code/*/README.md`: per-component notes.
- The model is described in the BSAT working paper (forthcoming on SSRN, https://www.ssrn.com/); the code is the authoritative specification.

## Layout

```
code/         processing (R), model (Julia), visualization (Python)
data/         raw, processed, packages (model inputs), scenarios (shocks template and case CSVs), outputs (example model outputs)
doc/          documentation site source
scripts/      bootstrap, run, and fetch scripts for the portable install
setup/        conda environments: environment.yml (R, pipeline) and environment-dashboard.yml (Python, local dashboard, optional)
.devcontainer Codespaces and Docker definition
```

## Contributors

| Name | Role | Affiliation |
|---|---|---|
| Diego S. Cardoso | Principal investigator, software and model design | University of Illinois Urbana-Champaign |
| Russell Hillberry | Co-Principal investigator, model design | Purdue University |
| Manuel I. Jimenez | Technical leader, model design and implementation, calibration, data pipeline | Purdue University |
| Hao Xiong | Model calibration, data pipeline | Purdue University |
| Yuansen Li | Data pipeline | Purdue University |
| Yongzhen Peng | Dashboard design | University of Illinois Urbana-Champaign |
| Ji Yong Kwon | Data specification, software design | Purdue University |

Funding: U.S. Department of Agriculture, Economic Research Service (Cooperative Agreement 58-3000-2-0085).

The model, pipeline and dashboard were written by the contributors listed above. Claude Code (Anthropic), with several Claude models, assisted the assembly of this release: integrating that code into one package, the installation and run scripts, the tests, and the documentation.

## How to cite

Cardoso, D. S., Hillberry, R., Jimenez, M. I., Xiong, H., Li, Y., Peng, Y., & Kwon, J. Y. (2026). *BSAT: Baseline Scenario Analysis Tool* (Version 1.0.0) [Computer software]. https://github.com/BSAT-team/BSAT

The BSAT working paper is forthcoming on SSRN; its reference and DOI will be added here when it is posted.

```bibtex
@software{bsat2026,
  author  = {Cardoso, Diego S. and Hillberry, Russell and Jimenez, Manuel I. and Xiong, Hao and Li, Yuansen and Peng, Yongzhen and Kwon, Ji Yong},
  title   = {{BSAT}: Baseline Scenario Analysis Tool},
  version = {1.0.0},
  year    = {2026},
  month   = {11},
  url     = {https://github.com/BSAT-team/BSAT}
}
```

The same metadata is in `CITATION.cff` (GitHub's "Cite this repository" button).

## License

Code is released under the MIT License (`LICENSE`). Documentation and the processed data products are released under CC BY 4.0 (`LICENSE-DOCS-DATA.md`). Raw data remain under their sources' terms, listed in `doc/data-sources.qmd`.
