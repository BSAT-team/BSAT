#!/usr/bin/env julia
# One command from an edited shocks CSV to a solved scenario: build the input package from the
# template, print the rows that differ from it, run the model, write the output package.
#
#   julia --project=code/model code/model/run_scenario.jl --shocks <edited.csv> [--output <Output.zip>]
#         [--description "text"] [--template <Input.zip>] [--years 2025:2034] [--build-only] [--license <path>]
#
# The CSV is a full or partial copy of data_shocks.csv (columns region, year, commodity,
# attribute, value; see data/scenarios/README.md). The input package is written beside the
# output package with the same stem (my_case_Output.zip -> my_case_Input.zip).

using Pkg
Pkg.activate(@__DIR__; io=devnull)
include(joinpath(@__DIR__, "src", "BSATRunner.jl"))
using .BSATRunner

const BSAT_DEFAULT_TEMPLATE = normpath(joinpath(@__DIR__, "..", "..", "data", "packages", "baseline_2025_Input.zip"))

function bsat_parse_scenario_args(args)
    opts = Dict{String,Any}("template" => BSAT_DEFAULT_TEMPLATE, "years" => "2025:2034", "build-only" => false)
    i = 1
    while i <= length(args)
        a = args[i]
        if a in ("-h", "--help")
            println("""
            Usage: julia --project=code/model code/model/run_scenario.jl --shocks <edited.csv> [options]
              --output <Output.zip>   output package (default: output/<csv name>_Output.zip); the input
                                      package is written beside it as <stem>_Input.zip
              --description "text"    scenario description written to METADATA.csv (default: the CSV name)
              --template <Input.zip>  package whose data_shocks.csv is edited (default: data/packages/baseline_2025_Input.zip)
              --years <from:to>       years to simulate (default: 2025:2034); a comma list also works
              --build-only            write the input package and print the changes; do not run the model
              --license <path>        PATH license file (default: code/model/path_license.txt)""")
            exit(0)
        elseif a == "--build-only"
            opts["build-only"] = true
        elseif startswith(a, "--") && i < length(args)
            opts[a[3:end]] = args[i + 1]; i += 1
        else
            error("Unrecognized argument: $a (use --help)")
        end
        i += 1
    end
    haskey(opts, "shocks") || error("--shocks <edited.csv> is required (use --help)")
    stem = replace(basename(opts["shocks"]), r"\.csv$"i => "")
    haskey(opts, "output") || (opts["output"] = joinpath("output", stem * "_Output.zip"))
    return opts
end

"Input package path beside the output package: my_case_Output.zip -> my_case_Input.zip."
function bsat_input_path(output_zip::AbstractString)
    stem = replace(basename(output_zip), r"(_Output)?\.zip$"i => "")
    return joinpath(dirname(output_zip), stem * "_Input.zip")
end

function bsat_parse_scenario_years(s::AbstractString)
    m = match(r"^\s*(\d{4})\s*[:-]\s*(\d{4})\s*$", s)
    m !== nothing && return parse(Int, m[1]):parse(Int, m[2])
    return [parse(Int, strip(y)) for y in split(s, ',')]
end

let opts = bsat_parse_scenario_args(ARGS)
    input_zip = bsat_input_path(opts["output"])
    built = build_scenario(opts["template"], opts["shocks"], input_zip; description=get(opts, "description", nothing))
    println("Input package written to: ", built.inputpkg_zip, " (", built.rows_applied, " row(s) applied, ",
            built.rows_skipped, " skipped, ", built.rows_changed, " differ from the template)")
    if opts["build-only"]
        println("Build only: the model was not run. Run it with run_model.jl --input ", built.inputpkg_zip)
    else
        kw = Dict{Symbol,Any}(:output_zip => opts["output"], :periods => bsat_parse_scenario_years(opts["years"]))
        haskey(opts, "license") && (kw[:license] = opts["license"])
        res = run_bsat(built.inputpkg_zip; kw...)
        println("Years solved:  ", join(string.(res.periods_solved), " "))
        isempty(res.periods_skipped) || println("Years skipped: ", join(string.(res.periods_skipped), " "))
        println("Elapsed:       ", round(res.elapsed; digits=1), " s")
    end
end
