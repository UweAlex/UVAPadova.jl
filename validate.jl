# validate_model.jl
# Vergleicht Julia-UVA/Padova mit simglucose-Referenzdaten in data/reference/.
# Kein Python nötig — reines Julia.

using Pkg
using Dates
Pkg.activate(@__DIR__)

include("src/patients.jl")
include("src/model.jl")
include("src/fast.jl")

using CSV, DataFrames, Statistics, Printf

REF_DIR = joinpath(@__DIR__, "data", "reference")
meta_path = joinpath(REF_DIR, "index.csv")

if !isfile(meta_path)
    error("Index nicht gefunden! Bitte zuerst:\n  julia reorganize_data.jl")
end

meta = CSV.read(meta_path, DataFrame)
println("📊 $(nrow(meta)) Testfälle geladen aus data/reference/index.csv\n")

function override_params(p::UVAPatientParams, overrides::Dict{Symbol,Float64})
    if isempty(overrides)
        return p
    end
    fields = fieldnames(UVAPatientParams)
    vals = Float64[haskey(overrides, f) ? overrides[f] : Float64(getfield(p, f)) for f in fields]
    UVAPatientParams(vals...)
end

results = DataFrame(
    test_id=String[], patient=String[], scenario=String[],
    param_override=String[],
    mae=Float64[], rmse=Float64[], max_error=Float64[], n_points=Int[]
)

for row in eachrow(meta)
    print(@sprintf("%-45s ", row.test_id))

    csv_path = joinpath(REF_DIR, row.file)
    if !isfile(csv_path)
        println("⚠ CSV fehlt: $(row.file)")
        continue
    end

    gt = CSV.read(csv_path, DataFrame)

    time_candidates = filter(c -> lowercase(string(c)) in ["time", "t"], names(gt))
    bg_candidates   = filter(c -> lowercase(string(c)) in ["bg", "blood_glucose"], names(gt))
    if isempty(time_candidates) || isempty(bg_candidates)
        println("⚠ Spalten nicht gefunden: $(names(gt))")
        continue
    end
    gt = select(gt, first(time_candidates) => :t, first(bg_candidates) => :BG_gt)
    
    times = DateTime.(gt.t, dateformat"yyyy-mm-dd HH:MM:SS")
    gt.t = Float64.(Dates.value.(times .- times[1]) ./ 60_000)  # ms → min

    # Testfall-Parameter rekonstruieren
    meals_min_str  = ismissing(row.meals_min) ? "" : row.meals_min
    meals_cho_str  = ismissing(row.meals_cho) ? "" : row.meals_cho
    boluses_min_str = ismissing(row.boluses_min) ? "" : row.boluses_min
    boluses_dose_str = ismissing(row.boluses_dose) ? "" : row.boluses_dose

    if meals_min_str == "" || meals_cho_str == ""
        println("⚠ Meals-Daten fehlen")
        continue
    end

    meals_min = parse.(Int, split(meals_min_str, ";"))
    meals_cho = parse.(Int, split(meals_cho_str, ";"))
    meals = [(time=t, cho=c) for (t, c) in zip(meals_min, meals_cho)]

    bol_min  = parse.(Int, split(boluses_min_str, ";"))
    bol_dose = parse.(Float64, split(boluses_dose_str, ";"))
    boluses = [(time=t, dose=d) for (t, d) in zip(bol_min, bol_dose)]

    # Patient + Overrides
    p = Patient(Symbol(row.patient))
    overrides = Dict{Symbol,Float64}()
    override_str = ""
    override_name = ismissing(row.param_override_name) ? "" : row.param_override_name
    override_value = ismissing(row.param_override_value) ? "" : string(row.param_override_value)
    if override_name != ""
        overrides[Symbol(override_name)] = override_value isa Number ? Float64(override_value) : parse(Float64, override_value)
        override_str = "$(override_name)=$(override_value)"
    end
    new_params = override_params(p.params, overrides)
    p = Patient(p.name, new_params, copy(p.initial_state))

    res = simulate_fast(p;
        meals   = meals,
        insulin = boluses,
        basal   = row.basal,
        T       = row.duration_min,
        save_every = 5
    )

    common_t = intersect(res.t, gt.t)
    if isempty(common_t)
        println("⚠ keine gemeinsamen Zeitpunkte")
        continue
    end

    bg_julia = res.BG[indexin(common_t, res.t)]
    bg_gt    = gt.BG_gt[indexin(common_t, gt.t)]

    mae = mean(abs.(bg_julia .- bg_gt))
    rmse = sqrt(mean((bg_julia .- bg_gt).^2))
    max_err = maximum(abs.(bg_julia .- bg_gt))

    push!(results, (row.test_id, row.patient, row.scenario, override_str,
                    mae, rmse, max_err, length(common_t)))
    @printf("MAE=%7.2f  Max=%7.2f  (%d pts)\n", mae, max_err, length(common_t))
end

# Ergebnisse
sort!(results, :max_error, rev=true)
out_path = joinpath(@__DIR__, "data", "validation_results.csv")
CSV.write(out_path, results)

println("\n" * "═"^60)
println("✅ VALIDATION FERTIG! $(nrow(results)) Tests")
println("   Ergebnisse: $out_path")

std_results  = filter(r -> r.param_override == "", results)
pert_results = filter(r -> r.param_override != "", results)

if nrow(std_results) > 0
    println("\n── Standard-Tests ($(nrow(std_results))) ──")
    @printf("   Mittlere MAE:  %.4f mg/dL\n", mean(std_results.mae))
    @printf("   Max Error:     %.4f mg/dL\n", maximum(std_results.max_error))
    good = count(r -> r.max_error < 1.0, eachrow(std_results))
    @printf("   Max-Error < 1 mg/dL: %d/%d (%.0f%%)\n",
            good, nrow(std_results), 100*good/nrow(std_results))
end

if nrow(pert_results) > 0
    println("\n── Perturbation-Tests ($(nrow(pert_results))) ──")
    @printf("   Mittlere MAE:  %.4f mg/dL\n", mean(pert_results.mae))
    @printf("   Max Error:     %.4f mg/dL\n", maximum(pert_results.max_error))
    good = count(r -> r.max_error < 1.0, eachrow(pert_results))
    @printf("   Max-Error < 1 mg/dL: %d/%d (%.0f%%)\n",
            good, nrow(pert_results), 100*good/nrow(pert_results))
end

println("\nSchlimmste 15 Abweichungen:")
println(first(results, 15))