# BSAT model runner

Julia/JuMP implementation of the BSAT model (mixed complementarity problem solved with PATH).

| File | Role |
|---|---|
| `src/model_core.jl` | The model, verbatim (data preparation, calibration, equations, solve, per-year results). Not to be edited. |
| `src/BSATRunner.jl`, `src/io.jl`, `src/run.jl` | Wrapper: reads the input package, runs the core year by year, writes the output package. |
| `run_model.jl` | Command-line entry point. |
| `make_shock.jl`, `src/shocks.jl` | Shock authoring: derive a scenario package from a template by editing `data_shocks.csv`. |
| `run_scenario.jl`, `src/scenario.jl` | Scenario from an edited shocks CSV (full or partial): build the package, print the changes, run the model. |
| `test/runtests.jl` | Regression test against archived reference outputs. |
| `path_license.txt` | PATH solver license (see `path_license.txt.example`). |

## Run

From the repository root:

```
julia --project=code/model code/model/run_model.jl --input data/packages/baseline_2025_Input.zip --output output/baseline_Output.zip
```

Options: `--years 2025:2034`, `--workdir <folder>`, `--keep-workdir`, `--license <path>`, `--help`.
The scripts in `scripts/run_model_*` call this with the defaults above.

From Julia:

```julia
include("code/model/src/BSATRunner.jl"); using .BSATRunner
res = run_bsat("data/packages/baseline_2025_Input.zip"; output_zip="output/baseline_Output.zip", periods=2025:2034)
res.periods_solved
```

## Run a scenario from an edited shocks CSV

```
julia --project=code/model code/model/run_scenario.jl --shocks data/scenarios/case1_land_supply_ukraine.csv \
      --output output/case1_Output.zip --description "Ukraine land supply 20 percent lower in 2026"
```

The CSV is a copy of `data_shocks.csv` with edited values, or only the rows to change (columns `region`, `year`, `commodity`, `attribute`, `value`; see `data/scenarios/README.md`). The input package is written beside the output as `case1_Input.zip`. Rows that cannot be applied are skipped with a warning. `--build-only` writes the package and prints the changes without running the model. The scripts in `scripts/run_scenario_*` call this.

## Author a shock

```
julia --project=code/model code/model/make_shock.jl --list
julia --project=code/model code/model/make_shock.jl --template data/packages/baseline_2025_Input.zip \
      --inputpkg output/case_Input.zip --shock shock_land_supply --value -0.10 --regions USA --years 2026:2034 \
      --description "US land supply 10 percent lower from 2026"
```

Shocks are decimals applied additively to the baseline level (neutral value 0). Run the command again with the previous package as template to layer shocks.

## Packages

Input: a zip holding `data_params_init.csv`, `data_exogenous.csv`, `data_targets.csv`, `data_shocks.csv`, and optionally `METADATA.csv`, with or without a leading folder.
Output: `data_params_calibrated.csv`, `data_exogenous.csv`, `data_shocks.csv`, `data_solution.csv`, `data_targets_adjusted.csv`, `METADATA.csv`, `SCENARIO_SOLVER_LOG.txt`, at the archive root.
The format is specified in `doc/data/data_specification.md`.

## Test

```
julia --project=code/model code/model/test/runtests.jl
```

Checks `make_shock` and `build_scenario` (`test/test_scenario.jl`, about a minute, runnable on its own), then runs the 2025 baseline package and the model authors' unharmonized July 2026 package (`test/fixtures/Input_2025_authors.zip`, about two minutes each), compares every data CSV with the checksums in `test/expected/`, and checks that both runs give the same solution file.
