# run_full_validation.jl
# Komplette Validation: Julia UVA/Padova vs. simglucose (Python)

using Pkg
Pkg.activate(@__DIR__)

println("✅ Setup abgeschlossen.\n")

# ── Dein Model laden ──
include("src/patients.jl")
include("src/model.jl")

using CSV, DataFrames, Statistics, Printf
using PythonCall, CondaPkg

CondaPkg.resolve()

# Diagnose
pyexec("""
import sys
print(f"Python: {sys.version}")
import simglucose
print(f"simglucose OK: {simglucose.__file__}")
""", Main)

py = PythonCall.pyimport

# ── Python-Simulations-Funktion einmal definieren ──
pyexec("""
import traceback
from simglucose.patient.t1dpatient import T1DPatient
from simglucose.sensor.cgm import CGMSensor
from simglucose.actuator.pump import InsulinPump
from simglucose.simulation.env import T1DSimEnv
from simglucose.simulation.scenario import CustomScenario
from simglucose.simulation.sim_engine import SimObj, sim
from simglucose.controller.base import Controller, Action
from datetime import datetime, timedelta

class OpenLoopController(Controller):
    def __init__(self, init_state, basal, boluses):
        super().__init__(init_state)
        self.basal = basal
        self.boluses = boluses
        self.t0 = None

    def policy(self, obs, reward, done, **info):
        st = info.get('sample_time')
        if st is None:
            return Action(basal=self.basal, bolus=0.0)
        if self.t0 is None:
            self.t0 = st
        try:
            minutes = (st - self.t0).total_seconds() / 60.0
        except AttributeError:
            minutes = float(st - self.t0)
        bolus = self.boluses.get(round(minutes), 0.0)
        return Action(basal=self.basal, bolus=bolus)

    def reset(self):
        self.t0 = None

def run_simglucose(patient_name, basal, meals_list, boluses_dict, duration_min, save_path):
    try:
        patient = T1DPatient.withName(patient_name)
        sensor = CGMSensor.withName('Dexcom', seed=42)
        pump = InsulinPump.withName('Insulet')
        scenario = CustomScenario(
            start_time=datetime(2025, 1, 1, 0, 0, 0),
            scenario=meals_list
        )
        ctrl = OpenLoopController(0, basal, boluses_dict)
        env = T1DSimEnv(patient=patient, sensor=sensor, pump=pump, scenario=scenario)
        s = SimObj(
            env=env,
            controller=ctrl,
            sim_time=timedelta(minutes=int(duration_min)),
            animate=False,
            path=save_path
        )
        sim(s)
        print(f"  -> Python sim OK: {patient_name}")
        return True
    except Exception as e:
        print(f"  -> FEHLER: {type(e).__name__}: {e}")
        traceback.print_exc()
        return False

print("Python-Funktionen definiert OK")
""", Main)

run_simglucose = pyeval("run_simglucose", Main)

# Testfälle
struct TestCase
    name::String
    patient_sym::Symbol
    basal::Float64
    meals::Vector{NamedTuple{(:time, :cho), Tuple{Int,Int}}}
    boluses::Vector{NamedTuple{(:time, :dose), Tuple{Int,Float64}}}
    duration_min::Float64
    start_bg::Union{Nothing,Float64}
    param_overrides::Dict{Symbol,Float64}
end

all_patients = vcat(
    [Symbol(@sprintf("child#%03d", i)) for i in 1:10],
    [Symbol(@sprintf("adolescent#%03d", i)) for i in 1:10],
    [Symbol(@sprintf("adult#%03d", i)) for i in 1:10]
)

standard_scenarios = [
    TestCase("standard_day", :placeholder, 0.8,
        [(time=60,cho=45),(time=720,cho=70),(time=960,cho=15),(time=1080,cho=80),(time=1380,cho=10)],
        [(time=55,dose=4.0)],
        1440.0, nothing, Dict{Symbol,Float64}()),
    TestCase("high_carb", :placeholder, 1.2,
        [(time=60,cho=80),(time=720,cho=110),(time=1080,cho=90)],
        [(time=50,dose=6.0),(time=710,dose=8.0)],
        1440.0, nothing, Dict{Symbol,Float64}()),
    TestCase("low_carb", :placeholder, 0.6,
        [(time=480,cho=30),(time=780,cho=40),(time=1140,cho=25)],
        [(time=470,dose=2.0)],
        1440.0, nothing, Dict{Symbol,Float64}()),
]

wild_cases = [
    TestCase("wild_bw100_start100", Symbol("adult#001"), 0.8,
        [(time=60,cho=45)], [(time=55,dose=4.0)], 1440.0, 100.0, Dict(:BW => 100.0)),
    TestCase("wild_high_sens", Symbol("adult#001"), 0.5,
        [(time=60,cho=60)], [(time=50,dose=6.0)], 1440.0, nothing, Dict(:kp1 => 2.5, :kp2 => 0.015)),
    TestCase("wild_low_sens", Symbol("child#001"), 1.5,
        [(time=60,cho=30)], [(time=55,dose=2.0)], 1440.0, nothing, Dict(:kp1 => 4.0, :kp2 => 0.005)),
    TestCase("wild_huge_meal", Symbol("adolescent#005"), 1.0,
        [(time=300,cho=150)], [(time=290,dose=12.0)], 1440.0, nothing, Dict{Symbol,Float64}()),
    TestCase("wild_start_bg60", Symbol("adult#003"), 0.7,
        [(time=60,cho=40)], [(time=55,dose=3.0)], 1440.0, 60.0, Dict{Symbol,Float64}()),
    TestCase("wild_start_bg180", Symbol("adult#007"), 0.9,
        [(time=60,cho=50)], [(time=55,dose=5.0)], 1440.0, 180.0, Dict{Symbol,Float64}()),
]

# Immutable struct → Felder per Rekonstruktion überschreiben
function override_params(p::UVAPatientParams, overrides::Dict{Symbol,Float64})
    if isempty(overrides)
        return p
    end
    fields = fieldnames(UVAPatientParams)
    vals = [haskey(overrides, f) ? overrides[f] : getfield(p, f) for f in fields]
    UVAPatientParams(vals...)
end

function create_test_patient(tc::TestCase)
    p = Patient(tc.patient_sym)
    new_params = override_params(p.params, tc.param_overrides)
    u0 = copy(p.initial_state)
    if !isnothing(tc.start_bg)
        u0[4] = tc.start_bg * new_params.Vg
    end
    Patient(p.name, new_params, u0)
end

results = DataFrame(test_name=String[], patient=String[], scenario=String[],
                    mae=Float64[], rmse=Float64[], max_error=Float64[], n_points=Int[])

SAVE_DIR = "validation_results"
mkpath(SAVE_DIR)

all_cases = vcat(
    [TestCase(sc.name, pat, sc.basal, sc.meals, sc.boluses, sc.duration_min, sc.start_bg, sc.param_overrides)
     for pat in all_patients for sc in standard_scenarios],
    wild_cases
)

println("🚀 Starte $(length(all_cases)) Tests…\n")

for (i, tc) in enumerate(all_cases)
    println(@sprintf("(%3d/%d) %s – %s", i, length(all_cases), tc.patient_sym, tc.name))

    p_julia = create_test_patient(tc)

    # ── Python-Simulation über die vordefinierte Funktion aufrufen ──
    patient_name_str = String(tc.patient_sym)
    save_path = replace(joinpath(@__DIR__, SAVE_DIR, tc.name), "\\" => "/")

    # Meals als Python-Liste von Tupeln: [(hour, cho), ...]
    meals_py = pylist([(Int(m.time ÷ 60), m.cho) for m in tc.meals])

    # Boluses als Python-Dict: {minute: dose, ...}
    boluses_py = pydict(Dict(round(Int, b.time) => b.dose for b in tc.boluses))

    success = run_simglucose(patient_name_str, tc.basal, meals_py, boluses_py,
                              tc.duration_min, save_path)

    if !pyconvert(Bool, success)
        println("  ⚠ Python-Simulation fehlgeschlagen, überspringe...")
        continue
    end

    # Ergebnis-CSV suchen
    csv_path = ""
    result_dir = joinpath(SAVE_DIR, tc.name)
    if isdir(result_dir)
        csvs = filter(f -> endswith(f, ".csv"), readdir(result_dir))
        if !isempty(csvs)
            csv_path = joinpath(result_dir, csvs[1])
            println("  → CSV: $(csvs[1])")
        end
    end
    if csv_path == "" || !isfile(csv_path)
        println("  ⚠ Keine CSV gefunden, überspringe...")
        continue
    end

    gt = CSV.read(csv_path, DataFrame)
    time_col = first(filter(c -> lowercase(string(c)) in ["time", "t"], names(gt)))
    bg_col   = first(filter(c -> lowercase(string(c)) in ["bg", "blood_glucose"], names(gt)))
    gt = select(gt, time_col => :t, bg_col => :BG_gt)

    res = simulate(p_julia;
        meals   = [(time=m.time, cho=m.cho) for m in tc.meals],
        insulin = [(time=b.time, dose=b.dose) for b in tc.boluses],
        basal   = tc.basal,
        T       = tc.duration_min,
        dt      = 5.0
    )

    common_t = intersect(res.t, gt.t)
    if isempty(common_t)
        println("  ⚠ Keine gemeinsamen Zeitpunkte, überspringe...")
        continue
    end
    bg_julia = res.BG[indexin(common_t, res.t)]
    bg_gt    = gt.BG_gt[indexin(common_t, gt.t)]

    mae = mean(abs.(bg_julia .- bg_gt))
    rmse = sqrt(mean((bg_julia .- bg_gt).^2))
    max_err = maximum(abs.(bg_julia .- bg_gt))

    push!(results, (tc.name, String(tc.patient_sym), tc.name, mae, rmse, max_err, length(common_t)))
    @printf("   → MAE = %.4f mg/dL   Max-Error = %.4f mg/dL\n", mae, max_err)
end

CSV.write(joinpath(SAVE_DIR, "validation_summary.csv"), results)
sort!(results, :max_error, rev=true)

println("\n" * "═"^70)
println("✅ VALIDATION FERTIG!")
println("Ergebnisse in: $SAVE_DIR/validation_summary.csv")
println("Schlimmste Abweichungen:")
println(first(results, 10))