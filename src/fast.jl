# fast.jl — AD-kompatibler UVA/Padova S2008 Simulator
#
# Ansatz: Segment-weise Tsit5-Integration. An jedem Mahlzeitbeginn wird
# der Solver gestoppt, qsto1+qsto2 abgelesen (für Dbar), und ein neues
# Segment gestartet. Kein mutabler State, keine Callbacks.
#
# Genauigkeit: Tsit5 adaptiv (1e-8), identisch mit simulate() in model.jl
# AD: ForwardDiff-kompatibel (Gradient, Jacobian über Parameter)

using ForwardDiff

# ===================================================================
# ODE-Kern (rein funktional, AD-sicher)
# ===================================================================

function ode_rhs!(du, u, p_tuple, t)
    params, meals, boluses, basal, qsto_at_starts = p_tuple

    qsto1, qsto2, qgut, gp, gt, ip, x, xl, id, il, isc1, isc2, gs = u

    # ── Eingaben ──
    cho_rate = zero(t)
    for m in meals
        t_end = m.time + m.cho / EAT_RATE
        if t >= m.time && t < t_end
            cho_rate += EAT_RATE * 1000.0
        end
    end

    ins_rate = basal
    for b in boluses
        if t >= b.time && t < b.time + BOLUS_DURATION
            ins_rate += b.dose / BOLUS_DURATION
        end
    end

    # ── Dbar (aus vorberechneten qsto-Werten) ──
    Dbar = zero(qsto1)
    for i in length(meals):-1:1
        if t >= meals[i].time && i <= length(qsto_at_starts)
            elapsed = t - meals[i].time
            foodtaken = min(elapsed * EAT_RATE, meals[i].cho)
            Dbar = qsto_at_starts[i] + foodtaken * 1000.0
            break
        end
    end

    # ── Magenentleerung ──
    qsto = qsto1 + qsto2
    if Dbar > 1e-6
        aa = 5 / (2 * Dbar * (1 - params.b))
        cc = 5 / (2 * Dbar * params.d)
        kgut = params.kmin + (params.kmax - params.kmin) / 2 * (
            tanh(aa * (qsto - params.b * Dbar)) -
            tanh(cc * (qsto - params.d * Dbar)) + 2)
    else
        kgut = params.kmax
    end

    du[1] = -params.kmax * qsto1 + cho_rate
    du[2] = params.kmax * qsto1 - kgut * qsto2
    du[3] = kgut * qsto2 - params.kabs * qgut

    # ── Glukose ──
    Rat  = params.f * params.kabs * qgut / params.BW
    EGPt = params.kp1 - params.kp2 * gp - params.kp3 * id
    Uiit = params.Fsnc
    Et   = gp > params.ke2 ? params.ke1 * (gp - params.ke2) : zero(gp)

    du[4] = max(EGPt, zero(EGPt)) + Rat - Uiit - Et - params.k1 * gp + params.k2 * gt

    Vmt  = params.Vm0 + params.Vmx * x
    Uidt = Vmt * gt / (params.Km0 + gt)
    du[5] = -Uidt + params.k1 * gp - params.k2 * gt

    # ── Insulin ──
    du[6] = -(params.m2 + params.m4) * ip + params.m1 * il + params.ka1 * isc1 + params.ka2 * isc2
    It = ip / params.Vi
    du[7] = -params.p2u * x + params.p2u * (It - params.Ib)
    du[8] = -params.ki * (xl - It)
    du[9] = -params.ki * (id - xl)
    du[10] = -(params.m1 + params.m30) * il + params.m2 * ip

    # ── Subkutanes Insulin ──
    ins_pmol = ins_rate * 6000 / params.BW
    du[11] = ins_pmol - (params.ka1 + params.kd) * isc1
    du[12] = params.kd * isc1 - params.ka2 * isc2

    # ── Subkutane Glukose ──
    du[13] = -params.ksc * gs + params.ksc * gp

    # ── Selektives Clamping ──
    du[4]  = gp   >= 0 ? du[4]  : zero(du[4])
    du[5]  = gt   >= 0 ? du[5]  : zero(du[5])
    du[6]  = ip   >= 0 ? du[6]  : zero(du[6])
    du[10] = il   >= 0 ? du[10] : zero(du[10])
    du[11] = isc1 >= 0 ? du[11] : zero(du[11])
    du[12] = isc2 >= 0 ? du[12] : zero(du[12])
    du[13] = gs   >= 0 ? du[13] : zero(du[13])

    nothing
end

# ===================================================================
# Segment-weise Tsit5-Integration
# ===================================================================

"""
    simulate_fast(params, u0, meals, boluses, basal, T; save_every=5,
                  reltol=1e-8, abstol=1e-8)

AD-kompatibler UVA/Padova Simulator. Segment-weise Tsit5-Integration:
an jedem Mahlzeitbeginn wird gestoppt, qsto abgelesen (für Dbar),
neues Segment gestartet. Kein mutabler State, keine Callbacks.

# Rückgabe
NamedTuple `(t, BG)`
"""
function simulate_fast(params::UVAPatientParams, u0,
                       meals, boluses, basal, T;
                       save_every::Int = 5,
                       reltol = 1e-8, abstol = 1e-8)

    sorted_meals = sort(collect(meals), by=m -> m.time)
    T_num = eltype(u0)

    # Segment-Grenzen: alle Sprungstellen (Mahlzeit + Bolus Start/Ende)
    boundaries = T_num[zero(T_num)]
    for m in sorted_meals
        m.time > 0 && m.time < T && push!(boundaries, T_num(m.time))
        t_end = m.time + m.cho / EAT_RATE
        t_end > 0 && t_end < T && push!(boundaries, T_num(t_end))
    end
    for b in boluses
        b.time > 0 && b.time < T && push!(boundaries, T_num(b.time))
        t_end = b.time + BOLUS_DURATION
        t_end > 0 && t_end < T && push!(boundaries, T_num(t_end))
    end
    push!(boundaries, T_num(T))
    unique!(sort!(boundaries))
    
    # Ausgabe-Zeitpunkte
    save_times = collect(zero(T_num):T_num(save_every):T_num(T))

    # qsto-Werte bei Mahlzeitbeginn
    qsto_at_starts = T_num[]

    # Sammle Ergebnisse
    all_t  = T_num[]
    all_bg = T_num[]

    u_current = collect(u0)

    for seg in 1:(length(boundaries)-1)
        t_start = boundaries[seg]
        t_end   = boundaries[seg+1]

        # Bei Mahlzeitbeginn: qsto aufzeichnen
        for m in sorted_meals
            if abs(t_start - m.time) < 0.01 && length(qsto_at_starts) < length(sorted_meals)
                push!(qsto_at_starts, u_current[1] + u_current[2])
            end
        end

        # qsto als Tuple einfrieren (immutabel, AD-sicher)
        qsto_frozen = Tuple(qsto_at_starts)

        # Saveat für dieses Segment
        seg_save = filter(t -> t >= t_start && t <= t_end, save_times)
        if isempty(seg_save)
            seg_save = [t_end]
        end

        p_tuple = (params, sorted_meals, boluses, basal, qsto_frozen)
        prob = ODEProblem(ode_rhs!, u_current, (t_start, t_end), p_tuple)
        sol = solve(prob, Tsit5(); saveat=seg_save, reltol, abstol)

        # Ergebnisse sammeln (keine Duplikate an Grenzen)
        for (i, t_i) in enumerate(sol.t)
            if isempty(all_t) || t_i > all_t[end] + 0.01
                push!(all_t, t_i)
                push!(all_bg, sol[4, i] / params.Vg)
            end
        end

        # Zustand am Segmentende → nächstes Segment
        u_current = sol[:, end]
    end

    (t = all_t, BG = all_bg)
end

# ===================================================================
# Convenience: Patient → simulate_fast
# ===================================================================
"""
    simulate_fast(patient::Patient; meals, insulin, basal, T, save_every)
"""
function simulate_fast(p::Patient;
                       meals = NamedTuple{(:time,:cho)}[],
                       insulin = NamedTuple{(:time,:dose)}[],
                       basal = 0.8,
                       T = 1440.0,
                       save_every::Int = 5)
    u0 = Float64.(p.initial_state)
    simulate_fast(p.params, u0, meals, insulin, basal, T; save_every)
end

# ===================================================================
# AD-Interface: θ-Vektor → BG-Kurve
# ===================================================================
"""
    simulate_with_θ(patient, θ, param_names; meals, insulin, basal, T, save_every)

Simuliert mit überschriebenen Parametern aus Vektor `θ`.
ForwardDiff-kompatibel für Gradient und Jacobian.

# Beispiel
```julia
using ForwardDiff
param_names = (:kp1, :Vmx)
θ = [p.params.kp1, p.params.Vmx]
J = ForwardDiff.jacobian(θ -> simulate_with_θ(p, θ, param_names; ...), θ)
```
"""
function simulate_with_θ(p::Patient, θ::AbstractVector, param_names::NTuple{N,Symbol};
                         meals = NamedTuple{(:time,:cho)}[],
                         insulin = NamedTuple{(:time,:dose)}[],
                         basal = 0.8,
                         T = 1440.0,
                         save_every::Int = 5) where N
    fields = fieldnames(UVAPatientParams)
    overrides = Dict(zip(param_names, θ))

    T_num = eltype(θ)
    vals = [haskey(overrides, f) ? overrides[f] : T_num(getfield(p.params, f)) for f in fields]
    new_params = UVAPatientParams(vals...)

    u0 = T_num.(p.initial_state)
    res = simulate_fast(new_params, u0, meals, insulin, basal, T; save_every)
    res.BG
end

export simulate_fast, simulate_with_θ
