# generate_reference.jl
# Erzeugt simglucose-Referenzdaten für Julia-Modellvalidierung.

using Pkg
Pkg.activate(@__DIR__)

using PythonCall, CondaPkg, Printf
using CSV, DataFrames

CondaPkg.resolve()

# ── Python-Code ──────────────────────────────────────────────
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

        bolus = self.boluses.get(int(round(minutes)), 0.0)
        return Action(basal=self.basal, bolus=bolus)

    def reset(self):
        self.t0 = None

def run_simglucose(patient_name, basal, meals_list, boluses_dict, duration_min, save_path,
                   param_overrides=None):
    try:
        base_patient = T1DPatient.withName(patient_name)
        params = base_patient._params.copy()

        if param_overrides:
            for k, v in param_overrides.items():
                if k in params.index:
                    params[k] = v

        patient = T1DPatient(params, init_state=None, random_init_bg=False, seed=None)

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
        return True

    except Exception as e:
        print(f"FEHLER: {type(e).__name__}: {e}")
        traceback.print_exc()
        return False

def get_patient_param_names(patient_name):
    p = T1DPatient.withName(patient_name)
    names = []
    for k in p._params.index:
        if k in ('Name', 'patient_history', 'i'):
            continue
        if str(k).startswith('x0'):
            continue
        try:
            float(p._params[k])
            names.append(k)
        except (ValueError, TypeError):
            pass
    return names

def get_patient_param_value(patient_name, param_name):
    p = T1DPatient.withName(patient_name)
    return float(p._params[param_name])

print("Python-Setup OK")
""", Main)

run_simglucose = pyeval("run_simglucose", Main)
get_patient_param_names = pyeval("get_patient_param_names", Main)
get_patient_param_value = pyeval("get_patient_param_value", Main)

# ─────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────
function main()

    REF_DIR = joinpath(@__DIR__, "reference_data")
    mkpath(REF_DIR)

    meta = DataFrame(
        test_id=String[], patient=String[], scenario=String[],
        basal=Float64[], duration=Float64[],
        meals_min=String[], meals_cho=String[],
        boluses_min=String[], boluses_dose=String[],
        param_override_name=String[], param_override_value=String[],
        csv_file=String[]
    )

    function find_csv_in_tree(save_dir)
        # Erst direkt im Ordner suchen
        csvs = sort(filter(f -> endswith(f, ".csv"), readdir(save_dir)))
        if !isempty(csvs)
            return csvs[1]
        end
        # Dann in Unterordnern
        for subdir in readdir(save_dir, join=true)
            if isdir(subdir)
                csvs = sort(filter(f -> endswith(f, ".csv"), readdir(subdir)))
                if !isempty(csvs)
                    return joinpath(basename(subdir), csvs[1])
                end
            end
        end
        return ""
    end

    function run_and_record!(test_id, patient, scenario_name, basal, meals, boluses,
                             duration, override_name, override_value, param_overrides)

        save_dir = joinpath(REF_DIR, test_id)

        if isdir(save_dir)
            rel = find_csv_in_tree(save_dir)
            if rel != ""
                push!(meta, (test_id, patient, scenario_name, basal, duration,
                             "", "", "", "", override_name, override_value,
                             joinpath(test_id, rel)))
                return :skipped
            end
        end

        mkpath(save_dir)

        # Windows-safe Pfad
        py_save_dir = replace(save_dir, "\\" => "/")

        meals_py = pylist([(m[1] / 60.0, m[2]) for m in meals])
        boluses_py = pydict(Dict(b[1] => b[2] for b in boluses))

        py_overrides = isempty(param_overrides) ?
            pyeval("None", Main) : pydict(param_overrides)

        success = run_simglucose(patient, basal, meals_py, boluses_py,
                                  duration, py_save_dir, py_overrides)

        if pyconvert(Bool, success)
            rel = find_csv_in_tree(save_dir)
            if rel != ""
                push!(meta, (test_id, patient, scenario_name, basal, duration,
                             "", "", "", "", override_name, override_value,
                             joinpath(test_id, rel)))
                return :ok
            end
        end

        return :failed
    end

    # ── Teil 1 ──
    all_patients = vcat(
        [@sprintf("child#%03d", i) for i in 1:10],
        [@sprintf("adolescent#%03d", i) for i in 1:10],
        [@sprintf("adult#%03d", i) for i in 1:10]
    )

    scenarios = [
        ("standard_day", 0.8, [(60,45),(720,70),(960,15),(1080,80),(1380,10)], [(55,4.0)], 1440.0),
        ("high_carb",    1.2, [(60,80),(720,110),(1080,90)], [(50,6.0),(710,8.0)], 1440.0),
        ("low_carb",     0.6, [(480,30),(780,40),(1140,25)], [(470,2.0)], 1440.0),
    ]

    total_std = length(all_patients) * length(scenarios)

    println("═"^60)
    println("TEIL 1: Standard-Tests ($total_std Tests)")
    println("═"^60)

    n_done = 0

    for patient in all_patients
        for (sc_name, basal, meals, boluses, dur) in scenarios
            n_done += 1
            test_id = "$(patient)_$(sc_name)"

            print(@sprintf("(%3d/%d) %s … ", n_done, total_std, test_id))

            result = run_and_record!(test_id, patient, sc_name,
                                     basal, meals, boluses, dur,
                                     "", "", Dict{String,Float64}())

            println(result == :ok ? "✅" : result == :skipped ? "⏭" : "❌")
        end
    end

    # ── Teil 2 ──
    BASE_PATIENT = "adult#001"
    sc_name, basal, meals, boluses, dur = scenarios[1]

    param_names = pyconvert(Vector{String}, get_patient_param_names(BASE_PATIENT))
    multipliers = [0.99, 1.01, 0.95, 1.05, 0.90, 1.10]

    total_perturb = length(param_names) * length(multipliers)

    println("\n" * "═"^60)
    println("TEIL 2: Parameter-Perturbation ($total_perturb Tests)")
    println("═"^60)

    n_done = 0

    for pname in param_names
        base_val = pyconvert(Float64, get_patient_param_value(BASE_PATIENT, pname))

        for mult in multipliers
            n_done += 1
            new_val = base_val * mult

            test_id = @sprintf("perturb_%s_x%.2f", pname, mult)

            print(@sprintf("(%3d/%d) %-10s = %10.4g … ",
                            n_done, total_perturb, pname, new_val))

            result = run_and_record!(test_id, BASE_PATIENT,
                                     "perturb_$(pname)",
                                     basal, meals, boluses, dur,
                                     pname, string(new_val),
                                     Dict(pname => new_val))

            println(result == :ok ? "✅" : result == :skipped ? "⏭" : "❌")
        end
    end

    # ── Save ──
    meta_path = joinpath(REF_DIR, "test_cases.csv")
    CSV.write(meta_path, meta)

    println("\n" * "═"^60)
    println("✅ REFERENZDATEN FERTIG!")
    println("   $(nrow(meta)) Tests")
    println("   Verzeichnis: $REF_DIR")
    println("   Metadaten:   $meta_path")
    println("═"^60)

end

# ── Start ──
main()