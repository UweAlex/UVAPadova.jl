function simulate(patient::Patient;
                  tspan = (0.0, 480.0),
                  meals = Tuple{Float64,Float64}[],
                  insulin = Tuple{Float64,Float64,Symbol}[],
                  basal = 0.0,
                  solver_config::Symbol = :dev)  # :dev (adaptiv) oder :fitting (fixed dt)

    u0 = copy(patient.initial_state)
    prob = ODEProblem((du,u,p,t) -> uvapadova_ode!(du, u, patient.params, t, meals, insulin, basal),
                      u0, tspan)

    if solver_config == :fitting
        sol = solve(prob, Tsit5(); adaptive=false, dt=1.0, saveat=1.0, abstol=1e-8, reltol=1e-6)
    else
        sol = solve(prob, Tsit5(); reltol=1e-6, abstol=1e-8)
    end

    # Post-processing
    BG = [sol[4,i] / patient.params.Vg * 18.0 for i in 1:length(sol.t)]  # mg/dL

    (t = sol.t, BG = BG, IOB = zeros(length(sol.t)), Ra = zeros(length(sol.t)), states = sol.u)
end

# LM-Ready
function residuals(patient::Patient, cgm_data::Vector{Float64}, θ::AbstractVector)
    # Beispiel: θ enthält zu fittende Parameter (später erweiterbar)
    # Hier Dummy – in U3 wird das erweitert
    sim = simulate(patient; tspan=(0, length(cgm_data)*1.0))
    sim.BG[1:length(cgm_data)] .- cgm_data
end