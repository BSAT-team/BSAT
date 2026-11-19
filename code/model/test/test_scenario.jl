# Tests of build_scenario (edited shocks CSV -> input package) and of the make_shock.jl command
# line. No model run; a few seconds.
#
#   julia --project=code/model code/model/test/test_scenario.jl
#
# Also included by runtests.jl.

if !isdefined(Main, :BSATRunner)
    using Pkg
    Pkg.activate(joinpath(@__DIR__, ".."); io=devnull)
    include(joinpath(@__DIR__, "..", "src", "BSATRunner.jl"))
end
using .BSATRunner, ZipFile, Test

const SCN_PACKAGES = joinpath(@__DIR__, "..", "..", "..", "data", "packages")
const SCN_TEMPLATE = joinpath(SCN_PACKAGES, "baseline_2025_Input.zip")

scn_entry(zipfile, name) = (r = ZipFile.Reader(zipfile); s = read(only(f for f in r.files if basename(f.name) == name)); close(r); s)

@testset "build_scenario" begin
    if !isfile(SCN_TEMPLATE)
        @warn "baseline package missing, build_scenario tests skipped" SCN_TEMPLATE
    else
        @testset "partial CSV reproduces case 1" begin
            dir = mktempdir()
            csv = joinpath(dir, "case1.csv")
            write(csv, "region,year,commodity,attribute,value\nUKR,2026,,shock_land_supply,-0.2\n")
            out = joinpath(dir, "case1_Input.zip")
            res = build_scenario(SCN_TEMPLATE, csv, out; description="case 1 test", io=devnull)
            @test res.rows_applied == 1
            @test res.rows_skipped == 0
            @test scn_entry(out, "data_shocks.csv") == scn_entry(joinpath(SCN_PACKAGES, "case1_land_supply_ukraine_Input.zip"), "data_shocks.csv")
        end

        @testset "malformed rows warn and are skipped" begin
            dir = mktempdir()
            csv = joinpath(dir, "bad.csv")
            write(csv, """region,year,commodity,attribute,value
                UKR,2026,,shock_land_supply,-0.2
                UKR,2026,,shock_not_a_thing,-0.2
                XXX,2026,,shock_land_supply,-0.2
                UKR,2050,,shock_land_supply,-0.2
                UKR,abcd,,shock_land_supply,-0.2
                UKR,2026,,shock_land_supply,minus ten
                UKR,2026,,shock_land_supply,
                UKR,2026,Wheat,shock_land_supply,-0.2
                UKR,2026,,shock_import_tariff,0.1
                UKR,2026,Bananas,shock_import_tariff,0.1
                UKR,2026,Beef,shock_land_prod,0.1
                """)
            out = joinpath(dir, "bad_Input.zip")
            res = @test_logs (:warn, r"unknown attribute") (:warn, r"unknown region") (:warn, r"year") (:warn, r"year") (:warn, r"value") (:warn, r"value") (:warn, r"region-level") (:warn, r"commodity") (:warn, r"unknown commodity") (:warn, r"not in the template") match_mode=:any build_scenario(SCN_TEMPLATE, csv, out; io=devnull)
            @test res.rows_read == 11
            @test res.rows_applied == 1
            @test res.rows_skipped == 10
            @test res.rows_changed == 1
            @test scn_entry(out, "data_shocks.csv") == scn_entry(joinpath(SCN_PACKAGES, "case1_land_supply_ukraine_Input.zip"), "data_shocks.csv")
        end

        @testset "duplicate key warns and the last row wins" begin
            dir = mktempdir()
            csv = joinpath(dir, "dup.csv")
            write(csv, "region,year,commodity,attribute,value\nUKR,2026,,shock_land_supply,-0.5\nUKR,2026,,shock_land_supply,-0.2\n")
            out = joinpath(dir, "dup_Input.zip")
            res = @test_logs (:warn, r"more than once") match_mode=:any build_scenario(SCN_TEMPLATE, csv, out; io=devnull)
            @test res.rows_applied == 2
            @test res.rows_changed == 1
            @test only(res.changes.value) == -0.2
        end

        @testset "no valid row is an error" begin
            dir = mktempdir()
            csv = joinpath(dir, "none.csv")
            write(csv, "region,year,commodity,attribute,value\nXXX,2026,,shock_land_supply,-0.2\n")
            logs, outcome = Test.collect_test_logs() do
                try build_scenario(SCN_TEMPLATE, csv, joinpath(dir, "x.zip"); io=devnull) catch e; e end
            end
            @test outcome isa ErrorException
            @test any(l -> occursin("unknown region", l.message), logs)
            write(csv, "region,year,attribute,value\nUKR,2026,shock_land_supply,-0.2\n")
            @test_throws ErrorException build_scenario(SCN_TEMPLATE, csv, joinpath(dir, "x.zip"); io=devnull)
        end

        @testset "spreadsheet spellings: BOM, CRLF, header case, code case, 2026.0, 1E-1" begin
            dir = mktempdir()
            csv = joinpath(dir, "excel.csv")
            write(csv, "﻿Region,YEAR,Commodity,Attribute,Value\r\nukr,2026.0,,shock_land_supply,-2E-1\r\n")
            out = joinpath(dir, "excel_Input.zip")
            res = @test_logs build_scenario(SCN_TEMPLATE, csv, out; io=devnull)
            @test res.rows_applied == 1
            @test scn_entry(out, "data_shocks.csv") == scn_entry(joinpath(SCN_PACKAGES, "case1_land_supply_ukraine_Input.zip"), "data_shocks.csv")
        end

        @testset "full edited copy of the template round-trips" begin
            dir = mktempdir()
            full = String(scn_entry(SCN_TEMPLATE, "data_shocks.csv"))
            lines = split(full, '\n')
            i = findfirst(l -> startswith(l, "UKR,2026,,,,shock_land_supply,0,"), lines)
            @test i !== nothing
            lines[i] = replace(lines[i], ",shock_land_supply,0," => ",shock_land_supply,-0.2,")
            csv = joinpath(dir, "full.csv")
            write(csv, "﻿" * join(lines, "\r\n"))
            out = joinpath(dir, "full_Input.zip")
            res = @test_logs build_scenario(SCN_TEMPLATE, csv, out; io=devnull)
            @test res.rows_read == 28980
            @test res.rows_applied == 28980
            @test res.rows_changed == 1
            @test scn_entry(out, "data_shocks.csv") == scn_entry(joinpath(SCN_PACKAGES, "case1_land_supply_ukraine_Input.zip"), "data_shocks.csv")
        end

        @testset "metadata and printout" begin
            dir = mktempdir()
            csv = joinpath(dir, "my_scenario.csv")
            write(csv, "region,year,commodity,attribute,value\n" *
                       join(["CHN,$y,Soybean,shock_import_tariff,0.1" for y in 2026:2034], "\n") * "\n" *
                       "IND,2026,Rice,shock_export_tax,0.5\nIND,2027,Rice,shock_export_tax,0.6\n")
            out = joinpath(dir, "my_Input.zip")
            buf = IOBuffer()
            res = build_scenario(SCN_TEMPLATE, csv, out; io=buf)
            text = String(take!(buf))
            @test occursin("shock_import_tariff", text) && occursin("CHN", text) && occursin("2026:2034 = 0.1", text)
            @test occursin("2026 = 0.5, 2027 = 0.6", text)
            md = String(scn_entry(out, "METADATA.csv"))
            @test occursin("Description,Scenario from my_scenario.csv", md)
            @test occursin("11 rows differ", md)
            res = build_scenario(SCN_TEMPLATE, csv, out; description="My scenario", io=devnull)
            @test occursin("Description,My scenario", String(scn_entry(out, "METADATA.csv")))
        end

        @testset "scenario equal to the template warns and proceeds" begin
            dir = mktempdir()
            csv = joinpath(dir, "zero.csv")
            write(csv, "region,year,commodity,attribute,value\nUKR,2026,,shock_land_supply,0\n")
            out = joinpath(dir, "zero_Input.zip")
            res = @test_logs (:warn, r"equals the template") match_mode=:any build_scenario(SCN_TEMPLATE, csv, out; io=devnull)
            @test res.rows_changed == 0
            @test isfile(out)
        end

        @testset "run_scenario.jl --build-only writes the input package beside the output" begin
            dir = mktempdir()
            csv = joinpath(dir, "case1.csv")
            write(csv, "region,year,commodity,attribute,value\nUKR,2026,,shock_land_supply,-0.2\n")
            script = joinpath(@__DIR__, "..", "run_scenario.jl")
            cmd = `$(Base.julia_cmd()) --project=$(joinpath(@__DIR__, "..")) $script --shocks $csv --output $(joinpath(dir, "case1_Output.zip")) --template $SCN_TEMPLATE --build-only --description "CLI test"`
            text = read(cmd, String)
            @test occursin("shock_land_supply", text) && occursin("UKR", text) && occursin("2026 = -0.2", text)
            @test isfile(joinpath(dir, "case1_Input.zip"))
            @test !isfile(joinpath(dir, "case1_Output.zip"))
            @test scn_entry(joinpath(dir, "case1_Input.zip"), "data_shocks.csv") == scn_entry(joinpath(SCN_PACKAGES, "case1_land_supply_ukraine_Input.zip"), "data_shocks.csv")
            @test occursin("Description,CLI test", String(scn_entry(joinpath(dir, "case1_Input.zip"), "METADATA.csv")))
        end

        @testset "shipped scenario CSVs rebuild the committed packages" begin
            scenarios = joinpath(@__DIR__, "..", "..", "..", "data", "scenarios")
            for (csv, pkg) in (("case1_land_supply_ukraine", "case1_land_supply_ukraine_Input.zip"),
                               ("case2_export_tax_india", "case2_export_tax_india_Input.zip"),
                               ("case3a_tfp_soybean_china", "case3a_tfp_soybean_china_Input.zip"),
                               ("case3b_tfp_soybean_china_half", "case3b_tfp_soybean_china_half_Input.zip"),
                               ("case4_land_productivity_usa", "case4_land_productivity_usa_Input.zip"),
                               ("example_china_soybean_tariff", "example_china_soybean_tariff_Input.zip"))
                out = joinpath(mktempdir(), csv * "_Input.zip")
                res = @test_logs build_scenario(SCN_TEMPLATE, joinpath(scenarios, csv * ".csv"), out; io=devnull)
                @test res.rows_skipped == 0
                @test scn_entry(out, "data_shocks.csv") == scn_entry(joinpath(SCN_PACKAGES, pkg), "data_shocks.csv")
            end
            # The template is the baseline shocks file: applying it changes nothing.
            out = joinpath(mktempdir(), "template_Input.zip")
            res = @test_logs (:warn, r"equals the template") build_scenario(SCN_TEMPLATE, joinpath(scenarios, "shocks_template.csv"), out; io=devnull)
            @test res.rows_applied == 28980 && res.rows_changed == 0
        end
    end
end

@testset "make_shock.jl command line" begin
    if !isfile(SCN_TEMPLATE)
        @warn "baseline package missing, make_shock.jl tests skipped" SCN_TEMPLATE
    else
        dir = mktempdir()
        proj = joinpath(@__DIR__, "..")
        script = joinpath(proj, "make_shock.jl")

        @testset "--inputpkg writes the scenario input package" begin
            pkg = joinpath(dir, "x_Input.zip")
            cmd = `$(Base.julia_cmd()) --project=$proj $script --template $SCN_TEMPLATE --inputpkg $pkg --shock shock_land_supply --value -0.1 --regions USA --years 2026:2034`
            text = read(cmd, String)
            @test isfile(pkg)
            @test startswith(strip(text), "Wrote")
            @test occursin(basename(pkg), text)
        end

        @testset "--output is rejected and points to --inputpkg" begin
            bad = joinpath(dir, "y_Input.zip")
            cmd = `$(Base.julia_cmd()) --project=$proj $script --template $SCN_TEMPLATE --output $bad --shock shock_land_supply --value -0.1 --regions USA --years 2026:2034`
            err = IOBuffer()
            p = run(pipeline(ignorestatus(cmd); stdout=devnull, stderr=err))
            @test !success(p)
            @test occursin("--inputpkg", String(take!(err)))
            @test !isfile(bad)
        end
    end
end
