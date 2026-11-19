# I/O helpers for BSATRunner: license, package extraction, output assembly, zip.

"""
    bsat_set_license!(path) -> String

Read the PATH license string from `path` (first line that is neither blank nor a `#`
comment) and register it with PATHSolver. Throws an informative error when the file is
missing or still holds the placeholder.
"""
function bsat_set_license!(path::AbstractString)
    isfile(path) || error("PATH license missing: create $(path) with your license string. " *
                          "Free license: https://pages.cs.wisc.edu/~ferris/path/LICENSE")
    key = ""
    for line in eachline(path)
        s = strip(line)
        (isempty(s) || startswith(s, "#")) && continue
        key = String(s)
        break
    end
    isempty(key) && error("$(path) has no license string (only blanks and comments).")
    occursin("PASTE-YOUR", key) && error("$(path) still contains the placeholder line; paste your PATH license string.")
    PATHSolver.c_api_License_SetString(key)
    return key
end

"""
    bsat_extract_input(zipfile, workdir) -> Dict{String,String}

Extract the standard input files from `zipfile` into `workdir/Input/`, matching entries by
file name so the archive may or may not carry a leading folder. Returns a map from file name
to extracted path. Errors if any of the four required files is absent.
"""
function bsat_extract_input(zipfile::AbstractString, workdir::AbstractString)
    isfile(zipfile) || error("Input package not found: $(zipfile)")
    indir = joinpath(workdir, "Input")
    mkpath(indir)
    wanted = Set([BSAT_INPUT_FILES..., "METADATA.csv"])
    found = Dict{String,String}()
    r = ZipFile.Reader(zipfile)
    try
        for f in r.files
            endswith(f.name, "/") && continue
            base = basename(f.name)
            base in wanted || continue
            dest = joinpath(indir, base)
            open(dest, "w") do io
                write(io, read(f))
            end
            found[base] = dest
        end
    finally
        close(r)
    end
    missing_files = [f for f in BSAT_INPUT_FILES if !haskey(found, f)]
    isempty(missing_files) || error("Input package $(zipfile) lacks: " * join(missing_files, ", "))
    return found
end

"Return the years in `periods` for which the core produced a solution file."
bsat_periods_solved(workdir, periods) =
    [i for i in periods if isfile(joinpath(workdir, "Output_$i", "data_solution.csv"))]

"""
    bsat_collect_output(workdir, periods_solved)

Assemble `workdir/Output/` from the per-year folders the core wrote. The file contents
reproduce the original code's overall export step (same column selections, same read and
write sequence), with the targets file renamed to `data_targets_adjusted.csv`.
"""
function bsat_collect_output(workdir::AbstractString, periods_solved::AbstractVector)
    outdir = joinpath(workdir, "Output")
    mkpath(outdir)
    # Parameters: calibrated subset of the exogenous file plus the initial parameters
    info_exogenous_ALL = CSV.read(joinpath(workdir, "Input", "data_exogenous.csv"), DataFrame)
    calib_attrs = ("sigma_t", "sigma_u", "sigma_n", "sigma_a", "sigma_i", "phi_i", "phi_f", "omega_q", "omega_c", "epsilon_l", "epsilon_q")
    data_parm_calb_A = info_exogenous_ALL[in.(info_exogenous_ALL.attribute, Ref(calib_attrs)), :]
    info_parameters_ALL = CSV.read(joinpath(workdir, "Input", "data_params_init.csv"), DataFrame)
    data_parm_calb_ALL = vcat(data_parm_calb_A, deepcopy(info_parameters_ALL))
    CSV.write(joinpath(outdir, "data_params_calibrated.csv"), data_parm_calb_ALL)
    # Exogenous data used by the model
    exo_attrs = ("International Price", "GDP per capita", "Population", "Price of No Land Input", "Price of No AG",
                 "P_NO_FEED", "inv_liv", "slt_liv", "Ag Expenditure Share", "NTM for exporting a product",
                 "NTM for importing a product", "Export tax", "Import tariff", "Land Unavailability ",
                 "TFP Productivity Value Added", "TFP Productivity Intermediates", "TFP Productivity Feed Use",
                 "Land Productivity")
    data_exogenous_sol_ALL = info_exogenous_ALL[in.(info_exogenous_ALL.attribute, Ref(exo_attrs)), :]
    CSV.write(joinpath(outdir, "data_exogenous.csv"), data_exogenous_sol_ALL)
    # Shocks: copied from the input
    info_Shocks_0_ALL = CSV.read(joinpath(workdir, "Input", "data_shocks.csv"), DataFrame)
    CSV.write(joinpath(outdir, "data_shocks.csv"), info_Shocks_0_ALL)
    # Solution and targets: concatenation of the per-year files
    empty_std() = DataFrame(region=Union{Missing,String}[], year=Int64[], nest=Union{Missing,String}[],
                            commodity=Union{Missing,String}[], input=Union{Missing,String}[],
                            attribute=Union{Missing,String}[], value=Union{Missing,Float64}[],
                            unit=Union{Missing,String}[], attribute_type=Union{Missing,String}[],
                            attribute_description=Union{Missing,String}[], region_name=Union{Missing,String}[],
                            nest_name=Union{Missing,String}[], commodity_name=Union{Missing,String}[])
    info_solution_ALL = empty_std()
    info_Targets_ALL = empty_std()
    for i in periods_solved
        append!(info_solution_ALL, CSV.read(joinpath(workdir, "Output_$i", "data_solution.csv"), DataFrame))
        append!(info_Targets_ALL, CSV.read(joinpath(workdir, "Output_$i", "data_targets.csv"), DataFrame))
    end
    CSV.write(joinpath(outdir, "data_solution.csv"), info_solution_ALL)
    CSV.write(joinpath(outdir, "data_targets_adjusted.csv"), info_Targets_ALL)
    return outdir
end

"""
    bsat_write_metadata(workdir, input_metadata, periods, periods_solved)

Write `Output/METADATA.csv`. Author, Description and Comments come from the input package's
`METADATA.csv` when present; otherwise the defaults of the original code are used.
"""
function bsat_write_metadata(workdir::AbstractString, input_metadata::Union{Nothing,AbstractString},
                             periods::AbstractVector, periods_solved::AbstractVector)
    fields = ["Author", "Description", "Comments"]
    values = Any["BSAT team", "Baseline scenario", "None"]
    if input_metadata !== nothing && isfile(input_metadata)
        md = CSV.read(input_metadata, DataFrame; types=String)
        if "field" in names(md) && "value" in names(md)
            for (k, v) in zip(md.field, md.value)
                idx = findfirst(==(k), fields)
                if idx === nothing
                    push!(fields, k); push!(values, coalesce(v, ""))
                else
                    values[idx] = coalesce(v, "")
                end
            end
        end
    end
    stamp = now()
    push!(fields, "Model calibration");  push!(values, stamp)
    push!(fields, "Scenario simulation"); push!(values, stamp)
    push!(fields, "Model version");       push!(values, BSAT_MODEL_VERSION)
    push!(fields, "Years requested");     push!(values, join(string.(periods), " "))
    push!(fields, "Years solved");        push!(values, join(string.(periods_solved), " "))
    CSV.write(joinpath(workdir, "Output", "METADATA.csv"), DataFrame(field=fields, value=values))
end

"""
    bsat_write_solver_log(workdir, periods, periods_solved, elapsed, console_log)

Write `Output/SCENARIO_SOLVER_LOG.txt`: run summary, per-year solver and model status as
recorded by the core, and the captured console output (which includes the PATH solver log).
"""
function bsat_write_solver_log(workdir::AbstractString, periods::AbstractVector, periods_solved::AbstractVector,
                               elapsed::Real, console_log::AbstractString)
    open(joinpath(workdir, "Output", "SCENARIO_SOLVER_LOG.txt"), "w") do io
        println(io, "BSAT scenario solver log")
        println(io, "Model version:   ", BSAT_MODEL_VERSION)
        println(io, "Run finished:    ", now())
        println(io, "Elapsed seconds: ", round(elapsed; digits=1))
        println(io, "Julia:           ", VERSION)
        println(io, "Years requested: ", join(string.(periods), " "))
        println(io, "Years solved:    ", join(string.(periods_solved), " "))
        skipped = setdiff(periods, periods_solved)
        println(io, "Years skipped:   ", isempty(skipped) ? "none" : join(string.(skipped), " "))
        println(io)
        println(io, "Per-year status (from Results_<year>/Solver_Status_Model_<year>.txt):")
        for i in periods
            f = joinpath(workdir, "Results_$i", "Solver_Status_Model_$i.txt")
            if isfile(f)
                for line in eachline(f)
                    println(io, "  ", i, "  ", line)
                end
            else
                println(io, "  ", i, "  not solved (market-clearing checks failed or solve skipped)")
            end
        end
        println(io)
        println(io, "Solver: PATH via PATHSolver.jl. Solver attributes are set in src/model_core.jl, section 5.")
        println(io)
        println(io, "=" ^ 100)
        println(io, "Console output")
        println(io, "=" ^ 100)
        if isfile(console_log)
            write(io, read(console_log, String))
        end
    end
end

"""
    bsat_zip_dir(dir, zipfile)

Zip every file directly under `dir` into `zipfile` with entries at the archive root
(no folder prefix), deflate-compressed. Platform independent.
"""
function bsat_zip_dir(dir::AbstractString, zipfile::AbstractString)
    mkpath(dirname(abspath(zipfile)))
    w = ZipFile.Writer(zipfile)
    try
        for name in sort(readdir(dir))
            path = joinpath(dir, name)
            isfile(path) || continue
            zf = ZipFile.addfile(w, name; method=ZipFile.Deflate)
            write(zf, read(path))
        end
    finally
        close(w)
    end
    return zipfile
end

"""
    bsat_tee_stdout(f, logpath)

Run `f()` while copying everything written to standard output (Julia and C level, so the
PATH solver output is included) both to the console and to `logpath`.
"""
function bsat_tee_stdout(f::Function, logpath::AbstractString)
    original = stdout
    rd, wr = redirect_stdout()
    logio = open(logpath, "w")
    copier = @async begin
        while !eof(rd)
            chunk = readavailable(rd)
            write(original, chunk); flush(original); write(logio, chunk); flush(logio)
        end
    end
    try
        return f()
    finally
        redirect_stdout(original)
        close(wr)
        wait(copier)
        close(logio)
    end
end
