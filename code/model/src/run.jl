# The run function: prepares a scratch working directory, evaluates the model core, assembles
# the output package.

"""
    run_bsat(input_zip; output_zip="Output.zip", periods=2025:2034, workdir=nothing,
             keep_workdir=false, license=BSAT_DEFAULT_LICENSE)

Run the BSAT model on the input package `input_zip` for the years in `periods` and write the
output package to `output_zip`. Returns a named tuple with `output_zip`, `periods_solved`,
`periods_skipped`, `elapsed` (seconds) and `workdir`.

- `workdir`: folder in which the core reads `Input/` and writes its per-year files. Defaults to
  a fresh temporary folder, deleted afterwards unless `keep_workdir=true`.
- `license`: path of the PATH license file.

Years the model refuses (market-clearing checks fail, or the solver does not reach a
solution) are skipped by the core and reported in `SCENARIO_SOLVER_LOG.txt` and in the return
value; the remaining years still produce output.
"""
function run_bsat(input_zip::AbstractString;
                  output_zip::AbstractString="Output.zip",
                  periods=2025:2034,
                  workdir::Union{Nothing,AbstractString}=nothing,
                  keep_workdir::Bool=false,
                  license::AbstractString=BSAT_DEFAULT_LICENSE)
    input_zip = abspath(input_zip)
    output_zip = abspath(output_zip)
    periods_vec = collect(Int, periods)
    isempty(periods_vec) && error("periods is empty")

    bsat_set_license!(license)
    setprecision(128)                      # BigFloat precision used by the core

    owns_workdir = workdir === nothing
    wd = owns_workdir ? mktempdir(; prefix="bsat_run_") : abspath(workdir)
    mkpath(wd)
    found = bsat_extract_input(input_zip, wd)
    console_log = joinpath(wd, "console_output.txt")

    original_dir = pwd()
    t0 = time()
    try
        cd(wd)
        # The core reads the global `periods` and loops over it; it is evaluated in this
        # module's global scope, exactly as the original script ran in Main.
        Core.eval(@__MODULE__, :(periods = $periods_vec))
        bsat_tee_stdout(console_log) do
            Base.include(@__MODULE__, BSAT_CORE_FILE)
        end
    finally
        cd(original_dir)
    end
    elapsed = time() - t0

    solved = bsat_periods_solved(wd, periods_vec)
    isempty(solved) && @warn "No year was solved; the output package contains no solution rows."
    bsat_collect_output(wd, solved)
    bsat_write_metadata(wd, get(found, "METADATA.csv", nothing), periods_vec, solved)
    bsat_write_solver_log(wd, periods_vec, solved, elapsed, console_log)
    bsat_zip_dir(joinpath(wd, "Output"), output_zip)
    println("Output package written to: ", output_zip)

    if owns_workdir && !keep_workdir
        rm(wd; recursive=true, force=true)
        wd = nothing
    end
    return (output_zip=output_zip, periods_solved=solved,
            periods_skipped=setdiff(periods_vec, solved), elapsed=elapsed, workdir=wd)
end
