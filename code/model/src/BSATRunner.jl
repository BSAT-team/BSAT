"""
    BSATRunner

Wrapper around the BSAT model core (`src/model_core.jl`, verbatim model code).

The module reads a standard input package (`Input.zip` with `data_params_init.csv`,
`data_exogenous.csv`, `data_targets.csv`, `data_shocks.csv`, optional `METADATA.csv`),
runs the model year by year, and writes a standard output package (`Output.zip` with
`data_params_calibrated.csv`, `data_exogenous.csv`, `data_shocks.csv`, `data_solution.csv`,
`data_targets_adjusted.csv`, `METADATA.csv`, `SCENARIO_SOLVER_LOG.txt`).

Entry points: [`run_bsat`](@ref) from Julia, or `run_model.jl` from the command line.

All wrapper names are prefixed `bsat_` so they cannot collide with variables assigned
inside the model core, which is evaluated in this module's global scope.
"""
module BSATRunner

using JuMP, DataFrames, PATHSolver, CSV, StatsBase, Printf, DataFramesMeta, Dates, ZipFile, MathOptInterface

export run_bsat, make_shock, build_scenario, BSAT_SHOCKS

"Version label of the model core embedded in this runner."
const BSAT_MODEL_VERSION = "v2.27 (2026-07-29)"

"Path of the verbatim model core."
const BSAT_CORE_FILE = joinpath(@__DIR__, "model_core.jl")

"Default location of the PATH license file (next to Project.toml)."
const BSAT_DEFAULT_LICENSE = normpath(joinpath(@__DIR__, "..", "path_license.txt"))

"Input files the model core reads from `Input/`."
const BSAT_INPUT_FILES = ("data_params_init.csv", "data_exogenous.csv", "data_targets.csv", "data_shocks.csv")

include("io.jl")
include("run.jl")
include("shocks.jl")
include("scenario.jl")

end # module
