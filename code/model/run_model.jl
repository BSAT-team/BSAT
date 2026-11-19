#!/usr/bin/env julia
# Command-line entry point for the BSAT model.
#
#   julia --project=code/model code/model/run_model.jl --input <Input.zip> [--output <Output.zip>]
#         [--years 2025:2034] [--workdir <folder>] [--keep-workdir] [--license <path>]
#
# Run from the repository root or from code/model; paths are resolved relative to the current
# directory. See doc/ for the walkthrough.

using Pkg
Pkg.activate(@__DIR__; io=devnull)
include(joinpath(@__DIR__, "src", "BSATRunner.jl"))
using .BSATRunner

function bsat_parse_args(args)
    opts = Dict{String,Any}("output" => "Output.zip", "years" => "2025:2034", "keep-workdir" => false)
    i = 1
    while i <= length(args)
        a = args[i]
        if a in ("-h", "--help")
            println("""
            Usage: julia --project=code/model code/model/run_model.jl --input <Input.zip> [options]
              --output <Output.zip>   output package (default: Output.zip in the current directory)
              --years <from:to>       years to simulate (default: 2025:2034); a comma list also works
              --workdir <folder>      working folder for the per-year files (default: a temporary folder)
              --keep-workdir          do not delete the working folder afterwards
              --license <path>        PATH license file (default: code/model/path_license.txt)""")
            exit(0)
        elseif a == "--keep-workdir"
            opts["keep-workdir"] = true
        elseif startswith(a, "--") && i < length(args)
            opts[a[3:end]] = args[i + 1]; i += 1
        else
            error("Unrecognized argument: $a (use --help)")
        end
        i += 1
    end
    haskey(opts, "input") || error("--input <Input.zip> is required (use --help)")
    return opts
end

function bsat_parse_years(s::AbstractString)
    m = match(r"^\s*(\d{4})\s*[:-]\s*(\d{4})\s*$", s)
    m !== nothing && return parse(Int, m[1]):parse(Int, m[2])
    return [parse(Int, strip(y)) for y in split(s, ',')]
end

let opts = bsat_parse_args(ARGS)
    kw = Dict{Symbol,Any}(:output_zip => opts["output"], :periods => bsat_parse_years(opts["years"]),
                          :keep_workdir => opts["keep-workdir"])
    haskey(opts, "workdir") && (kw[:workdir] = opts["workdir"])
    haskey(opts, "license") && (kw[:license] = opts["license"])
    res = run_bsat(opts["input"]; kw...)
    println("Years solved:  ", join(string.(res.periods_solved), " "))
    isempty(res.periods_skipped) || println("Years skipped: ", join(string.(res.periods_skipped), " "))
    println("Elapsed:       ", round(res.elapsed; digits=1), " s")
end
