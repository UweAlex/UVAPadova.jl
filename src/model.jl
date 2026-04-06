# model.jl
# UVA/Padova 2008 – validiert gegen simglucose t1dpatient.py
# MAE ~1.7 mg/dL über 366 Tests (30 Patienten × 3 Szenarien + 276 Perturbationen)
#
# Eingabemodell:
#   Mahlzeiten: Rechteckpuls, EAT_RATE=5 g/min (wie simglucose)
#   Insulin:    Rechteckpuls, 1 min Injektionsdauer (wie simglucose)
#   Dbar:       Zustandsbasiert (wie simglucose)

using CSV, DataFrames, StaticArrays, DifferentialEquations

# ===================================================================
# Konstanten (aus simglucose)
# ===================================================================
const EAT_RATE = 5.0          # g/min CHO
const BOLUS_DURATION = 1.0    # min Injektionsdauer

# ===================================================================
# Patient-Konstruktor
# ===================================================================
const PATIENT_CSV = joinpath(@__DIR__, "..", "data", "vpatient_params.csv")

function Patient(name::Symbol)
    df = CSV.read(PATIENT_CSV, DataFrame)
    row = df[df.Name .== String(name), :]
    if nrow(row) == 0
        error("Patient $name nicht gefunden!")
    end
    row = row[1, :]

   params = UVAPatientParams(
        BW=Float64(row.BW), kabs=Float64(row.kabs), kmax=Float64(row.kmax), kmin=Float64(row.kmin),
        b=Float64(row.b), d=Float64(row.d), f=Float64(row.f),
        Vg=Float64(row.Vg), Vm0=Float64(row.Vm0), Vmx=Float64(row.Vmx), Km0=Float64(row.Km0),
        k1=Float64(row.k1), k2=Float64(row.k2), Fsnc=Float64(row.Fsnc), ke1=Float64(row.ke1), ke2=Float64(row.ke2),
        kp1=Float64(row.kp1), kp2=Float64(row.kp2), kp3=Float64(row.kp3), ki=Float64(row.ki),
        Vi=Float64(row.Vi), Ib=Float64(row.Ib),
        m1=Float64(row.m1), m2=Float64(row.m2), m4=Float64(row.m4), m30=Float64(row.m30), p2u=Float64(row.p2u),
        ka1=Float64(row.ka1), ka2=Float64(row.ka2), kd=Float64(row.kd), ksc=Float64(row.ksc),
        EGPb=Float64(row.EGPb), Gb=Float64(row.Gb), Gpb=Float64(row.Gpb), Gtb=Float64(row.Gtb),
        Ipb=Float64(row.Ipb), Ilb=Float64(row.Ilb), u2ss=Float64(row.u2ss)
    )

    x0 = MVector{13,Float64}([
        row[:"x0_ 1"], row[:"x0_ 2"], row[:"x0_ 3"], row[:"x0_ 4"],
        row[:"x0_ 5"], row[:"x0_ 6"], row[:"x0_ 7"], row[:"x0_ 8"],
        row[:"x0_ 9"], row[:"x0_10"], row[:"x0_11"], row[:"x0_12"],
        row[:"x0_13"]
    ])

    Patient(String(name), params, x0)
end

# ===================================================================
# Eingabe-Funktionen
# ===================================================================

# Mahlzeit: Rechteckpuls (EAT_RATE g/min)
function meal_rate_rect(t, meals)
    d = 0.0
    for m in meals
        meal_end = m.time + m.cho / EAT_RATE
        if t >= m.time && t < meal_end
            d += EAT_RATE * 1000.0   # g/min → mg/min
        end
    end
    return d
end

# Insulin: Basal (kontinuierlich, U/min) + Bolus (Rechteck, 1 min)
function insulin_rate(t, boluses, basal)
    bolus_rate = 0.0
    for b in boluses
        if t >= b.time && t < b.time + BOLUS_DURATION
            bolus_rate += b.dose / BOLUS_DURATION   # U/min
        end
    end
    return basal + bolus_rate
end

# ===================================================================
# Dbar-Tracker (wie simglucose step() + model())
# ===================================================================
mutable struct DbarTracker
    qsto_at_start::Vector{Float64}
    recorded::Vector{Bool}
end

function DbarTracker(n_meals::Int)
    DbarTracker(zeros(n_meals), fill(false, n_meals))
end

function record_meal_start!(tracker::DbarTracker, meal_idx::Int, qsto1, qsto2)
    tracker.qsto_at_start[meal_idx] = qsto1 + qsto2
    tracker.recorded[meal_idx] = true
end

function compute_dbar(tracker::DbarTracker, t, meals)
    for i in length(meals):-1:1
        m = meals[i]
        if t >= m.time && tracker.recorded[i]
            elapsed = t - m.time
            foodtaken = min(elapsed * EAT_RATE, m.cho)
            return tracker.qsto_at_start[i] + foodtaken * 1000.0
        end
    end
    return 0.0
end

# ===================================================================
# ODE – korrigiert gegen simglucose t1dpatient.py
# ===================================================================
#
# Zustandsvektor:
#  u[1]  qsto1  Magen fest         u[8]  Xl   verzögerte Insulin-Wirkung 1
#  u[2]  qsto2  Magen flüssig      u[9]  Id   verzögerte Insulin-Wirkung 2
#  u[3]  qgut   Darm               u[10] Il   Leber-Insulin
#  u[4]  Gp     Plasma-Glukose     u[11] Isc1 Subkutanes Insulin 1
#  u[5]  Gt     Gewebe-Glukose     u[12] Isc2 Subkutanes Insulin 2
#  u[6]  Ip     Plasma-Insulin     u[13] Gs   Subkutane Glukose
#  u[7]  X      Insulin-Wirkung

function uvapadova_ode!(du, u, p::UVAPatientParams{<:Real}, t,
                        cho_rate_val, ins_rate_val, Dbar)
    @inbounds begin
        qsto1, qsto2, qgut, gp, gt, ip, x, xl, id, il, isc1, isc2, gs = u

        # ── Magenentleerung ──
        qsto = qsto1 + qsto2
        if Dbar > 1e-6
            aa = 5 / (2 * Dbar * (1 - p.b))
            cc = 5 / (2 * Dbar * p.d)
            kgut = p.kmin + (p.kmax - p.kmin)/2 * (
                tanh(aa*(qsto - p.b*Dbar)) - tanh(cc*(qsto - p.d*Dbar)) + 2
            )
        else
            kgut = p.kmax
        end

        du[1] = -p.kmax * qsto1 + cho_rate_val
        du[2] = p.kmax * qsto1 - kgut * qsto2
        du[3] = kgut * qsto2 - p.kabs * qgut

        # ── Glukose ──
        Rat  = p.f * p.kabs * qgut / p.BW
        EGPt = p.kp1 - p.kp2 * gp - p.kp3 * id
        Uiit = p.Fsnc
        Et   = (gp > p.ke2) ? p.ke1 * (gp - p.ke2) : 0.0

        du[4] = max(EGPt, 0.0) + Rat - Uiit - Et - p.k1 * gp + p.k2 * gt

        Vmt  = p.Vm0 + p.Vmx * x
        Uidt = Vmt * gt / (p.Km0 + gt)
        du[5] = -Uidt + p.k1 * gp - p.k2 * gt

        # ── Insulin ──
        du[6] = -(p.m2 + p.m4) * ip + p.m1 * il + p.ka1 * isc1 + p.ka2 * isc2
        It = ip / p.Vi
        du[7] = -p.p2u * x + p.p2u * (It - p.Ib)
        du[8] = -p.ki * (xl - It)
        du[9] = -p.ki * (id - xl)
        du[10] = -(p.m1 + p.m30) * il + p.m2 * ip

        # ── Subkutanes Insulin ──
        ins_pmol = ins_rate_val * 6000 / p.BW
        du[11] = ins_pmol - (p.ka1 + p.kd) * isc1
        du[12] = p.kd * isc1 - p.ka2 * isc2

        # ── Subkutane Glukose ──
        du[13] = -p.ksc * gs + p.ksc * gp

        # ── Selektives Clamping (wie simglucose) ──
        du[4]  = (gp   >= 0) ? du[4]  : 0.0
        du[5]  = (gt   >= 0) ? du[5]  : 0.0
        du[6]  = (ip   >= 0) ? du[6]  : 0.0
        du[10] = (il   >= 0) ? du[10] : 0.0
        du[11] = (isc1 >= 0) ? du[11] : 0.0
        du[12] = (isc2 >= 0) ? du[12] : 0.0
        du[13] = (gs   >= 0) ? du[13] : 0.0
    end
    nothing
end

# ===================================================================
# Simulate
# ===================================================================
struct SimulationResult
    t::Vector{Float64}
    BG::Vector{Float64}
end

function simulate(p::Patient;
                  meals::Vector = NamedTuple{(:time, :cho)}[],
                  insulin::Vector = NamedTuple{(:time, :dose)}[],
                  basal::Float64 = 0.8,
                  T::Float64 = 1440.0,
                  dt::Float64 = 5.0)

    tracker = DbarTracker(length(meals))

    u0 = copy(p.initial_state)
    tspan = (0.0, T)

    function ode_func!(du, u, _, t)
        cho_val = meal_rate_rect(t, meals)
        ins_val = insulin_rate(t, insulin, basal)
        Dbar    = compute_dbar(tracker, t, meals)
        uvapadova_ode!(du, u, p.params, t, cho_val, ins_val, Dbar)
    end

    # Callbacks: Solver an allen Sprungstellen stoppen
    meal_start_times = [m.time for m in meals]
    meal_end_times   = [m.time + m.cho / EAT_RATE for m in meals]
    bolus_start_times = [b.time for b in insulin]
    bolus_end_times   = [b.time + BOLUS_DURATION for b in insulin]
    all_stop_times = sort(unique(vcat(meal_start_times, meal_end_times,
                                      bolus_start_times, bolus_end_times)))

    function meal_affect!(integrator)
        t = integrator.t
        for (i, m) in enumerate(meals)
            if abs(t - m.time) < 0.01 && !tracker.recorded[i]
                record_meal_start!(tracker, i, integrator.u[1], integrator.u[2])
            end
        end
    end

    cb = PresetTimeCallback(all_stop_times, meal_affect!)

    prob = ODEProblem(ode_func!, u0, tspan)
    sol = solve(prob, Tsit5();
                saveat=0:dt:T,
                reltol=1e-8, abstol=1e-8,
                callback=cb)

    BG = [u[4] / p.params.Vg for u in sol.u]
    SimulationResult(sol.t, BG)
end

export Patient, simulate, SimulationResult, UVAPatientParams