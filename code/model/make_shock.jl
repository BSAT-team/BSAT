#!/usr/bin/env julia
# Command-line shock authoring: derive a scenario input package from a template package.
#
#   julia --project=code/model code/model/make_shock.jl --template <Input.zip> --inputpkg <Input.zip>
#         --shock <attribute> --value <decimal> [--regions USA,BRA] [--commodities Corn,Soybean]
#         [--years 2026:2034] [--add] [--description "text"]
#   julia --project=code/model code/model/make_shock.jl --list      (shows the ten shock attributes)
#
# Layer several shocks by running the command again with the previous package as template.

using Pkg
Pkg.activate(@__DIR__; io=devnull)
include(joinpath(@__DIR__, "src", "BSATRunner.jl"))
using .BSATRunner

function bsat_parse(args)
    opts = Dict{String,Any}("add" => false)
    i = 1
    while i <= length(args)
        a = args[i]
        if a in ("-h", "--help")
            println("""
            Usage: julia --project=code/model code/model/make_shock.jl --template <Input.zip> --inputpkg <Input.zip> --shock <attribute> --value <decimal> [options]
              --template <Input.zip> package whose data_shocks.csv is edited (required)
              --inputpkg <Input.zip> scenario input package to write (required); it is the input of
                                     the next step, run_model.jl --input <Input.zip>
              --regions A,B,C        ISO-3 region codes (default: all)
              --commodities A,B      commodity codes (default: all; ignored for region-level shocks)
              --years 2026:2034      years, a range or a comma list (default: all)
              --add                  add to the existing value instead of replacing it
              --description "text"   scenario description written to METADATA.csv
              --list                 print the shock attributes and their meaning""")
            exit(0)
        elseif a == "--list"
            for (name, typ, meaning) in BSAT_SHOCKS
                println(rpad(name, 44), " [", typ, "]  ", meaning)
            end
            exit(0)
        elseif a == "--add"
            opts["add"] = true
        elseif a == "--output"
            error("--output is not an option of make_shock.jl: the package it writes is an input package, use --inputpkg <Input.zip>")
        elseif startswith(a, "--") && i < length(args)
            opts[a[3:end]] = args[i + 1]; i += 1
        else
            error("Unrecognized argument: $a (use --help)")
        end
        i += 1
    end
    for k in ("template", "inputpkg", "shock", "value")
        haskey(opts, k) || error("--$k is required (use --help)")
    end
    return opts
end

bsat_list(s) = s === nothing ? nothing : String.(split(s, ','))
function bsat_years(s)
    s === nothing && return nothing
    m = match(r"^\s*(\d{4})\s*[:-]\s*(\d{4})\s*$", s)
    m !== nothing && return collect(parse(Int, m[1]):parse(Int, m[2]))
    return [parse(Int, strip(y)) for y in split(s, ',')]
end

let o = bsat_parse(ARGS)
    res = make_shock(o["template"], o["inputpkg"]; attribute=o["shock"], value=parse(Float64, o["value"]),
                     regions=bsat_list(get(o, "regions", nothing)), commodities=bsat_list(get(o, "commodities", nothing)),
                     years=bsat_years(get(o, "years", nothing)), mode=o["add"] ? :add : :set,
                     description=get(o, "description", nothing))
    println("Wrote ", res.inputpkg_zip, ": ", res.rows_changed, " rows of \"", res.attribute, "\" set to ", res.value)
end
