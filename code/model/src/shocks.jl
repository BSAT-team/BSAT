# Shock authoring: derive a scenario input package from a template package by editing data_shocks.csv.

"""
The ten shock attributes of `data_shocks.csv`, with the baseline quantity each one modifies.
Every shock is stored in decimal form and applied additively to the baseline level, except
`shock_ag_expenditure_share`, which multiplies the baseline share by (1 + value). The neutral
value is 0 for all of them.
"""
const BSAT_SHOCKS = (
    ("shock_import_tariff",                        "RYNC", "ad valorem import tariff, added in decimal form (0.10 = +10 percentage points)"),
    ("shock_export_tax",                           "RYNC", "ad valorem export tax, added in decimal form"),
    ("shock_nontariff_import",                     "RYNC", "ad valorem equivalent of import non-tariff measures, added in decimal form"),
    ("shock_nontax_export",                        "RYNC", "ad valorem equivalent of export non-tax measures, added in decimal form"),
    ("shock_land_prod",                            "RYNC", "land productivity shifter, decimal change (-0.10 = 10 percent lower yields per hectare)"),
    ("shock TFP Productivity Value Added",         "RYNC", "total factor productivity shifter in value added, decimal change"),
    ("shock TFP Productivity Intermediates",       "RYNC", "total factor productivity shifter in intermediate use (soybean crushing), decimal change"),
    ("shock_TFP_Productivity_Feed_Use_livestock",  "RYNC", "total factor productivity shifter in feed use of livestock, decimal change"),
    ("shock_land_supply",                          "RY",   "land supply availability, decimal change (-0.10 = 10 percent less land), region level"),
    ("shock_ag_expenditure_share",                 "RY",   "agricultural expenditure share, proportional change (0.05 = 5 percent higher), region level"),
)

"""
    make_shock(template_zip, inputpkg_zip; attribute, value, regions=nothing, commodities=nothing,
               years=nothing, mode=:set, description=nothing) -> NamedTuple

Create a scenario input package from `template_zip` by editing `data_shocks.csv`. The package
written to `inputpkg_zip` is the *input* of a model run (`run_bsat` / `run_model.jl --input`).

- `attribute`: one of the ten shock attributes (see `BSAT_SHOCKS`).
- `value`: the shock in decimal form.
- `regions`, `commodities`, `years`: optional selections (vectors of ISO-3 codes, commodity codes,
  integer years). `nothing` selects every row of that attribute. Region-level shocks ignore
  `commodities`.
- `mode`: `:set` writes `value`; `:add` adds it to the existing value, which lets shocks be
  layered by calling the function repeatedly with the previous package as template.
- `description`: replaces the `Description` field of `METADATA.csv` (created if the template has
  no metadata file), so the dashboard shows what the scenario is.

Returns `(inputpkg_zip, rows_changed, attribute, value)`. Errors if no row matches the selection.
"""
function make_shock(template_zip::AbstractString, inputpkg_zip::AbstractString;
                    attribute::AbstractString, value::Real,
                    regions=nothing, commodities=nothing, years=nothing,
                    mode::Symbol=:set, description::Union{Nothing,AbstractString}=nothing)
    attribute in first.(BSAT_SHOCKS) || error("Unknown shock attribute \"$attribute\". Known: " * join(first.(BSAT_SHOCKS), ", "))
    mode in (:set, :add) || error("mode must be :set or :add")
    entries = bsat_read_zip_entries(template_zip)
    haskey(entries, "data_shocks.csv") || error("$(template_zip) has no data_shocks.csv")

    shocks = CSV.read(IOBuffer(entries["data_shocks.csv"]), DataFrame; stringtype=String)
    sel = shocks.attribute .== attribute
    regions     === nothing || (sel .&= in.(shocks.region, Ref(Set(String.(regions)))))
    commodities === nothing || (sel .&= in.(coalesce.(shocks.commodity, ""), Ref(Set(String.(commodities)))))
    years       === nothing || (sel .&= in.(shocks.year, Ref(Set(Int.(years)))))
    n = count(sel)
    n > 0 || error("No row of \"$attribute\" matches the selection (regions=$(regions), commodities=$(commodities), years=$(years))")
    shocks.value = Float64.(coalesce.(shocks.value, 0.0))
    shocks.value[sel] .= mode == :set ? value : shocks.value[sel] .+ value
    buf = IOBuffer(); CSV.write(buf, shocks); entries["data_shocks.csv"] = take!(buf)

    if description !== nothing
        bsat_set_metadata!(entries; description=description,
            comment="Derived from $(basename(template_zip)) with make_shock: $(attribute) = $(value)" *
                    (mode == :add ? " (added)" : ""))
    end

    bsat_write_zip_entries(inputpkg_zip, entries)
    return (inputpkg_zip=abspath(inputpkg_zip), rows_changed=n, attribute=attribute, value=value)
end

"Read every file entry of a zip into a Dict basename => bytes (folder prefixes dropped)."
function bsat_read_zip_entries(zipfile::AbstractString)
    isfile(zipfile) || error("Package not found: $(zipfile)")
    entries = Dict{String,Vector{UInt8}}()
    r = ZipFile.Reader(zipfile)
    try
        for f in r.files
            endswith(f.name, "/") && continue
            entries[basename(f.name)] = read(f)
        end
    finally
        close(r)
    end
    return entries
end

"Write entries (basename => bytes) under an Input/ folder, the layout of the input packages."
function bsat_write_zip_entries(zipfile::AbstractString, entries::Dict{String,Vector{UInt8}})
    mkpath(dirname(abspath(zipfile)))
    w = ZipFile.Writer(zipfile)
    try
        for name in sort(collect(keys(entries)))
            zf = ZipFile.addfile(w, "Input/" * name; method=ZipFile.Deflate)
            write(zf, entries[name])
        end
    finally
        close(w)
    end
    return zipfile
end
