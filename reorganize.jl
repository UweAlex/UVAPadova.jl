# reorganize_data.jl
# Konsolidiert alle Referenzdaten in data/reference/ mit vollständiger Index-CSV.
# Füllt fehlende Meals/Boluses-Daten aus den Szenario-Definitionen nach.

using Pkg
Pkg.activate(@__DIR__)
using CSV, DataFrames

SRC_DIR = joinpath(@__DIR__, "reference_data")
DST_DIR = joinpath(@__DIR__, "data", "reference")
mkpath(DST_DIR)

meta_path = joinpath(SRC_DIR, "test_cases.csv")
if !isfile(meta_path)
    error("test_cases.csv nicht gefunden in $SRC_DIR")
end

meta = CSV.read(meta_path, DataFrame)
println("📂 $(nrow(meta)) Tests gefunden\n")

# ── Szenario-Definitionen (für fehlende Meals/Boluses) ──
SCENARIOS = Dict(
    "standard_day" => (
        meals_min="60;720;960;1080;1380", meals_cho="45;70;15;80;10",
        boluses_min="55", boluses_dose="4.0"),
    "high_carb" => (
        meals_min="60;720;1080", meals_cho="80;110;90",
        boluses_min="50;710", boluses_dose="6.0;8.0"),
    "low_carb" => (
        meals_min="480;780;1140", meals_cho="30;40;25",
        boluses_min="470", boluses_dose="2.0"),
)

# Perturbation-Tests nutzen standard_day
function get_scenario_data(scenario_name)
    # "perturb_BW" → Basis ist standard_day
    base = startswith(scenario_name, "perturb_") ? "standard_day" : scenario_name
    return get(SCENARIOS, base, SCENARIOS["standard_day"])
end

# ── Index aufbauen ──
index = DataFrame(
    file=String[],
    test_id=String[],
    patient=String[],
    scenario=String[],
    basal=Float64[],
    duration_min=Float64[],
    meals_min=String[],
    meals_cho=String[],
    boluses_min=String[],
    boluses_dose=String[],
    param_override_name=String[],
    param_override_value=String[],
    n_rows=Int[],
    columns=String[]
)

copied = 0
skipped = 0

for row in eachrow(meta)
    global copied, skipped
    src_csv = joinpath(SRC_DIR, row.csv_file)
    if !isfile(src_csv)
        println("  ⚠ fehlt: $(row.csv_file)")
        skipped += 1
        continue
    end

    # Sauberer Dateiname
    dst_name = row.test_id * ".csv"
    dst_csv = joinpath(DST_DIR, dst_name)
    cp(src_csv, dst_csv; force=true)

    # CSV inspizieren
    df = CSV.read(dst_csv, DataFrame)
    col_names = join(names(df), ";")

    # Fehlende Meals/Boluses aus Szenario nachfüllen
    sc_data = get_scenario_data(row.scenario)

    meals_min_str  = (ismissing(row.meals_min) || row.meals_min == "") ?
                      sc_data.meals_min : row.meals_min
    meals_cho_str  = (ismissing(row.meals_cho) || row.meals_cho == "") ?
                      sc_data.meals_cho : row.meals_cho
    bol_min_str    = (ismissing(row.boluses_min) || row.boluses_min == "") ?
                      sc_data.boluses_min : row.boluses_min
    bol_dose_str   = (ismissing(row.boluses_dose) || row.boluses_dose == "") ?
                      sc_data.boluses_dose : row.boluses_dose

    override_name  = ismissing(row.param_override_name) ? "" : row.param_override_name
    override_value = ismissing(row.param_override_value) ? "" : string(row.param_override_value)
    push!(index, (
        dst_name, row.test_id, row.patient, row.scenario,
        row.basal, row.duration,
        meals_min_str, meals_cho_str, bol_min_str, bol_dose_str,
        override_name, override_value,
        nrow(df), col_names
    ))

    copied += 1
end

# Speichern
index_path = joinpath(DST_DIR, "index.csv")
CSV.write(index_path, index)
CSV.write(joinpath(@__DIR__, "data", "reference_index.csv"), index)

println("\n" * "═"^60)
println("✅ REORGANISATION FERTIG!")
println("   $copied Dateien → data/reference/")
println("   $skipped übersprungen")
println("   Index: data/reference/index.csv")
println("═"^60)
println("\nDanach kann der alte Ordner weg:")
println("   rmdir /s /q reference_data")
println("\nNächster Schritt:")
println("   julia validate_model.jl")