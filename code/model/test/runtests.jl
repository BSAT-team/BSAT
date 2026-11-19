# Regression test: the runner must reproduce the archived reference outputs byte for byte.
#
#   julia --project=code/model code/model/test/runtests.jl
#
# Each case runs the model on a fixture package and compares the SHA-256 of every data CSV in
# the output package with test/expected/<fixture>.sha256 (METADATA and the solver log carry
# timestamps and are not compared). Runtime is about two minutes per case. The make_shock and
# build_scenario checks (test_scenario.jl, no model run) come first.

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."); io=devnull)
include(joinpath(@__DIR__, "..", "src", "BSATRunner.jl"))
using .BSATRunner, SHA, ZipFile, Test

# The pipeline's package (harmonized targets) and the model authors' July 2026 package (the same
# targets before harmonization, so the model applies its own repairs). Both must reproduce their
# checksums, and both must give the same data_solution.csv: that is the check that the pipeline's
# harmonization step (code/processing/R/50_harmonize_targets.R) mirrors the model.
const CASES = [
    (fixture=joinpath(@__DIR__, "..", "..", "..", "data", "packages", "baseline_2025_Input.zip"), periods=2025:2034, expected="baseline_2025_Input"),
    (fixture=joinpath(@__DIR__, "fixtures", "Input_2025_authors.zip"),                     periods=2025:2034, expected="Input_2025_authors"),
]

function sha256_of_entries(zipfile)
    out = Dict{String,String}()
    r = ZipFile.Reader(zipfile)
    for f in r.files
        out[basename(f.name)] = bytes2hex(sha256(read(f)))
    end
    close(r)
    return out
end

function read_expected(name)
    d = Dict{String,String}()
    for line in eachline(joinpath(@__DIR__, "expected", name * ".sha256"))
        h, f = split(strip(line), r"\s+"; limit=2)
        d[String(f)] = String(h)
    end
    return d
end

@testset "make_shock" begin
    template = joinpath(@__DIR__, "..", "..", "..", "data", "packages", "baseline_2025_Input.zip")
    if isfile(template)
        out = joinpath(mktempdir(), "shock_Input.zip")
        res = make_shock(template, out; attribute="shock_land_supply", value=-0.1, regions=["USA"], years=2026:2034,
                         description="test")
        @test res.rows_changed == 9
        got = sha256_of_entries(out)
        for f in ("data_params_init.csv", "data_exogenous.csv", "data_targets.csv", "data_shocks.csv", "METADATA.csv")
            @test haskey(got, f)
        end
        r = ZipFile.Reader(out)
        shocks = String(read(only(f for f in r.files if endswith(f.name, "data_shocks.csv"))))
        close(r)
        nonzero = count(l -> occursin(",shock_land_supply,-0.1,", l), split(shocks, '\n'))
        @test nonzero == 9
        @test_throws ErrorException make_shock(template, out; attribute="not_a_shock", value=1.0)
        @test_throws ErrorException make_shock(template, out; attribute="shock_land_supply", value=1.0, regions=["XXX"])
    else
        @warn "baseline package missing, make_shock test skipped" template
    end
end

include(joinpath(@__DIR__, "test_scenario.jl"))

@testset "BSAT regression" begin
    solution_hash = Dict{String,String}()
    for c in CASES
        isfile(c.fixture) || (@warn "fixture missing, skipped" c.fixture; continue)
        out = joinpath(mktempdir(), "Output.zip")
        res = run_bsat(c.fixture; output_zip=out, periods=c.periods)
        @test res.periods_solved == collect(c.periods)
        got = sha256_of_entries(out)
        for (f, h) in read_expected(c.expected)
            @test haskey(got, f)
            haskey(got, f) && @test got[f] == h
        end
        @test haskey(got, "METADATA.csv") && haskey(got, "SCENARIO_SOLVER_LOG.txt")
        haskey(got, "data_solution.csv") && (solution_hash[c.expected] = got["data_solution.csv"])
    end
    @testset "harmonized and unharmonized packages give the same solution" begin
        if haskey(solution_hash, "baseline_2025_Input") && haskey(solution_hash, "Input_2025_authors")
            @test solution_hash["baseline_2025_Input"] == solution_hash["Input_2025_authors"]
        else
            @warn "one of the two packages did not run; solution comparison skipped"
        end
    end
end
