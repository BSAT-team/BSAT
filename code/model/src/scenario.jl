# Scenario building: turn an edited copy of data_shocks.csv (full or partial) into an input package.

"Columns of an edited shocks CSV that build_scenario reads; every other column is ignored."
const BSAT_SCENARIO_COLUMNS = ("region", "year", "commodity", "attribute", "value")

"""
    build_scenario(template_zip, shocks_csv, inputpkg_zip; description=nothing, io=stdout) -> NamedTuple

Create a scenario input package from `template_zip` by writing the values of `shocks_csv` into
its `data_shocks.csv`. The CSV can be a full edited copy of the shocks file or only the rows to
change; rows are matched on region, year, commodity and attribute, and rows absent from the CSV
keep the template value. The shocks file of the package is regenerated from the template table,
so the spreadsheet's formatting never reaches the model.

Only the columns region, year, commodity, attribute and value are read (header case and
surrounding blanks ignored; region and commodity codes matched case-insensitively). A row that
cannot be applied (unknown attribute, region or commodity, a commodity on a region-level
attribute or none on a commodity-level one, a year outside the template, a blank or non-numeric
value, a region and commodity pair the model does not have) is reported in a warning and
skipped. When a key appears more than once the last row wins. The function errors if no row can
be applied, and warns if the result equals the template.

The rows that differ from the template are printed to `io`, grouped by attribute, region and
commodity. `description` goes to the `Description` field of `METADATA.csv` (default: the CSV
name); the `Comments` field records the source and the count of changed rows.

Returns `(inputpkg_zip, rows_read, rows_applied, rows_skipped, rows_changed, changes)`, where
`changes` is a DataFrame of the rows whose value differs from the template.
"""
function build_scenario(template_zip::AbstractString, shocks_csv::AbstractString, inputpkg_zip::AbstractString;
                        description::Union{Nothing,AbstractString}=nothing, io::IO=stdout)
    entries = bsat_read_zip_entries(template_zip)
    haskey(entries, "data_shocks.csv") || error("$(template_zip) has no data_shocks.csv")
    shocks = CSV.read(IOBuffer(entries["data_shocks.csv"]), DataFrame; stringtype=String)
    shocks.value = Float64.(coalesce.(shocks.value, 0.0))
    shocks.commodity = String.(coalesce.(shocks.commodity, ""))
    original = copy(shocks.value)

    # Lookup tables built from the template: canonical spellings and the row of every key.
    index = Dict{Tuple{String,Int,String,String},Int}()
    for (i, r) in enumerate(eachrow(shocks))
        index[(r.region, r.year, r.commodity, r.attribute)] = i
    end
    attr_type   = Dict(name => typ for (name, typ, _) in BSAT_SHOCKS)
    attr_by_key = Dict(bsat_norm(name) => name for name in keys(attr_type))
    region_by_key    = Dict(bsat_norm(c) => c for c in unique(shocks.region))
    commodity_by_key = Dict(bsat_norm(c) => c for c in unique(shocks.commodity) if !isempty(c))
    years = Set(shocks.year)

    user = bsat_read_scenario_csv(shocks_csv)
    problems = Dict{String,Vector{Int}}()          # reason => CSV line numbers
    seen = Dict{Tuple{String,Int,String,String},Int}()  # key => CSV line of the last row applied
    applied = 0
    for (i, r) in enumerate(eachrow(user))
        line = i + 1                               # header is line 1
        reason = nothing
        attribute = get(attr_by_key, bsat_norm(r.attribute), nothing)
        region    = get(region_by_key, bsat_norm(r.region), nothing)
        commodity = isempty(r.commodity) ? "" : get(commodity_by_key, bsat_norm(r.commodity), nothing)
        year      = bsat_parse_year(r.year)
        value     = bsat_parse_value(r.value)
        if attribute === nothing
            reason = "unknown attribute \"$(r.attribute)\" (see make_shock.jl --list)"
        elseif region === nothing
            reason = "unknown region code \"$(r.region)\""
        elseif commodity === nothing
            reason = "unknown commodity code \"$(r.commodity)\""
        elseif attr_type[attribute] == "RY" && !isempty(commodity)
            reason = "commodity given for the region-level attribute \"$(attribute)\" (leave it blank)"
        elseif attr_type[attribute] == "RYNC" && isempty(commodity)
            reason = "no commodity for the commodity-level attribute \"$(attribute)\""
        elseif year === nothing || !(year in years)
            reason = "year \"$(r.year)\" is not a template year ($(minimum(years)) to $(maximum(years)))"
        elseif value === nothing
            reason = isempty(r.value) ? "blank value" : "value \"$(r.value)\" is not a number"
        elseif !haskey(index, (region, year, commodity, attribute))
            reason = "row not in the template: the model has no \"$(attribute)\" for $(region) $(commodity)"
        end
        if reason !== nothing
            push!(get!(problems, reason, Int[]), line)
            continue
        end
        key = (region, year, commodity, attribute)
        if haskey(seen, key)
            push!(get!(problems, "key given more than once; the last row wins", Int[]), seen[key])
        end
        seen[key] = line
        shocks.value[index[key]] = value
        applied += 1
    end
    skipped = nrow(user) - applied
    for reason in sort(collect(keys(problems)))
        lines = problems[reason]
        shown = join(string.(first(lines, 10)), ", ") * (length(lines) > 10 ? ", ..." : "")
        @warn "$(basename(shocks_csv)): $(length(lines)) row(s) skipped, $(reason). Line(s) $(shown)"
    end
    applied > 0 || error("No row of $(shocks_csv) could be applied (see the warnings above)")

    changed = findall(shocks.value .!= original)
    isempty(changed) && @warn "$(basename(shocks_csv)): every applied value equals the template; the scenario equals $(basename(template_zip))"
    changes = shocks[changed, [:attribute, :region, :commodity, :year, :value]]
    bsat_print_changes(io, changes, basename(template_zip))

    buf = IOBuffer(); CSV.write(buf, shocks); entries["data_shocks.csv"] = take!(buf)
    bsat_set_metadata!(entries;
        description=something(description, "Scenario from $(basename(shocks_csv))"),
        comment="Built with build_scenario from $(basename(shocks_csv)): $(length(changed)) rows differ from $(basename(template_zip))")
    bsat_write_zip_entries(inputpkg_zip, entries)
    return (inputpkg_zip=abspath(inputpkg_zip), rows_read=nrow(user), rows_applied=applied, rows_skipped=skipped,
            rows_changed=length(changed), changes=changes)
end

"Key used to match codes and attribute names regardless of case and surrounding blanks."
bsat_norm(s::AbstractString) = lowercase(strip(s))

"Parse a year cell; accepts spreadsheet spellings such as `2026.0`. `nothing` if not an integer."
function bsat_parse_year(s::AbstractString)
    x = tryparse(Float64, s)
    (x === nothing || !isfinite(x) || !isinteger(x)) && return nothing
    return Int(x)
end

"Parse a value cell. `nothing` if blank, not a number, or not finite."
function bsat_parse_value(s::AbstractString)
    x = tryparse(Float64, s)
    return (x === nothing || !isfinite(x)) ? nothing : x
end

"""
Read an edited shocks CSV as strings: every cell trimmed, missing cells as empty strings, headers
matched case-insensitively. Errors if a required column is missing.
"""
function bsat_read_scenario_csv(path::AbstractString)
    isfile(path) || error("Shocks CSV not found: $(path)")
    raw = CSV.read(path, DataFrame; types=String, stringtype=String, silencewarnings=true, strict=false)
    lookup = Dict(bsat_norm(String(n)) => n for n in names(raw))
    missing_cols = [c for c in BSAT_SCENARIO_COLUMNS if !haskey(lookup, c)]
    isempty(missing_cols) || error("$(path) lacks the column(s) " * join(missing_cols, ", ") *
                                   "; required: " * join(BSAT_SCENARIO_COLUMNS, ", "))
    out = DataFrame()
    for c in BSAT_SCENARIO_COLUMNS
        out[!, c] = String[strip(coalesce(v, "")) for v in raw[!, lookup[c]]]
    end
    return out
end

"""
Print the changed rows grouped by attribute, region and commodity, one line per group: a run of
consecutive years with the same value is written `2026:2034 = -0.1`, other years one by one.
"""
function bsat_print_changes(io::IO, changes::DataFrame, template_name::AbstractString)
    if nrow(changes) == 0
        println(io, "No row differs from ", template_name, ".")
        return
    end
    println(io, nrow(changes), " row(s) differ from ", template_name, ":")
    for g in groupby(sort(changes, [:attribute, :region, :commodity, :year]), [:attribute, :region, :commodity]; sort=true)
        label = rpad(g.attribute[1], 44) * rpad(g.region[1], 5) * rpad(isempty(g.commodity[1]) ? "-" : g.commodity[1], 9)
        println(io, "  ", label, bsat_format_runs(g.year, g.value))
    end
end

"Format year/value pairs (sorted by year) compressing runs of consecutive years with equal values."
function bsat_format_runs(years::AbstractVector{<:Integer}, values::AbstractVector{<:Real})
    parts = String[]
    i = 1
    while i <= length(years)
        j = i
        while j < length(years) && years[j + 1] == years[j] + 1 && values[j + 1] == values[i]
            j += 1
        end
        push!(parts, j > i ? "$(years[i]):$(years[j]) = $(values[i])" : "$(years[i]) = $(values[i])")
        i = j + 1
    end
    return join(parts, ", ")
end

"""
Set the `Description` and `Comments` fields of the package's METADATA.csv in `entries`, creating
the file when the template has none.
"""
function bsat_set_metadata!(entries::Dict{String,Vector{UInt8}}; description::AbstractString, comment::AbstractString)
    md = haskey(entries, "METADATA.csv") ?
         CSV.read(IOBuffer(entries["METADATA.csv"]), DataFrame; types=String) :
         DataFrame(field=["Author", "Description", "Comments"], value=["BSAT team", "", ""])
    for (field, text) in (("Description", description), ("Comments", comment))
        idx = findfirst(==(field), md.field)
        idx === nothing ? push!(md, (field, text)) : (md.value[idx] = text)
    end
    buf = IOBuffer(); CSV.write(buf, md); entries["METADATA.csv"] = take!(buf)
    return entries
end
