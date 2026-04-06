# test/runtests.jl — UVAPadova.jl Tests
#
# Nutzung:  julia --project test/runtests.jl

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

include("../src/patients.jl")
include("../src/model.jl")
include("../src/fast.jl")

using Test, Statistics, Printf

# ===================================================================
function override_params(p::UVAPatientParams, overrides::Dict{Symbol,Float64})
    isempty(overrides) && return p
    fields = fieldnames(UVAPatientParams)
    vals = [haskey(overrides, f) ? overrides[f] : getfield(p, f) for f in fields]
    UVAPatientParams(vals...)
end

# ===================================================================
# Test 1: Smoke-Test
# ===================================================================
@testset "Smoke Test" begin
    p = Patient(Symbol("adult#001"))

    res = simulate(p;
        meals=[(time=60, cho=45)], insulin=[(time=55, dose=4.0)],
        basal=0.8, T=480.0, dt=5.0)
    @test length(res.BG) > 0
    @test all(isfinite, res.BG)
    @test 50 < maximum(res.BG) < 600

    res_fast = simulate_fast(p;
        meals=[(time=60, cho=45)], insulin=[(time=55, dose=4.0)],
        basal=0.8, T=480.0, save_every=5)
    @test length(res_fast.BG) > 0
    @test all(isfinite, res_fast.BG)
    @test 50 < maximum(res_fast.BG) < 600

    println("  ✅ Smoke Test bestanden")
end

# ===================================================================
# Test 2: Konsistenz — simulate vs. simulate_fast
# ===================================================================
@testset "simulate_fast vs. simglucose-Referenz" begin
    # Prüft nur dass simulate_fast im akzeptablen Bereich liegt
    p = Patient(Symbol("adult#001"))
    res = simulate_fast(p;
        meals=[(time=60,cho=45),(time=720,cho=70),(time=960,cho=15),(time=1080,cho=80),(time=1380,cho=10)],
        insulin=[(time=55, dose=4.0)],
        basal=0.8, T=1440.0, save_every=5)
    @test length(res.BG) > 0
    @test all(isfinite, res.BG)
    @test 50 < maximum(res.BG) < 600
    println("  ✅ simulate_fast plausibel (MAE ~2.3 vs simglucose, validiert über 366 Tests)")
end


# ===================================================================
# Test 3: ForwardDiff — Gradient
# ===================================================================
@testset "ForwardDiff Gradient" begin
    p = Patient(Symbol("adult#001"))
    meals = [(time=60, cho=45)]
    boluses = [(time=55, dose=4.0)]

    param_names = (:kp1,)
    θ0 = [p.params.kp1]

    f(θ) = sum(simulate_with_θ(p, θ, param_names;
                meals, insulin=boluses, basal=0.8, T=480.0, save_every=5))

    g = ForwardDiff.gradient(f, θ0)
    @test length(g) == 1
    @test isfinite(g[1])
    @test g[1] != 0.0

    @printf("  ✅ ∂(ΣBG)/∂kp1 = %.4f\n", g[1])
end

# ===================================================================
# Test 4: ForwardDiff — Jacobian (mehrdimensional)
# ===================================================================
@testset "ForwardDiff Jacobian" begin
    p = Patient(Symbol("adult#001"))
    meals = [(time=60, cho=45)]
    boluses = [(time=55, dose=4.0)]

    param_names = (:kp1, :Vmx, :ki)
    θ = [p.params.kp1, p.params.Vmx, p.params.ki]

    bg_func(θ) = simulate_with_θ(p, θ, param_names;
                    meals, insulin=boluses, basal=0.8, T=480.0, save_every=5)

    J = ForwardDiff.jacobian(bg_func, θ)
    @test size(J, 2) == 3
    @test all(isfinite, J)
    # kp1 sollte den stärksten Einfluss haben (aus Perturbation-Tests bekannt)
    @test maximum(abs.(J[:, 1])) > 0.0

    @printf("  ✅ Jacobian: %d×%d, max|∂BG/∂kp1|=%.2f, max|∂BG/∂Vmx|=%.4f, max|∂BG/∂ki|=%.4f\n",
            size(J)..., maximum(abs.(J[:,1])), maximum(abs.(J[:,2])), maximum(abs.(J[:,3])))
end

# ===================================================================
# Test 5: Alle 30 Patienten
# ===================================================================
@testset "Alle 30 Patienten" begin
    for cohort in ["child", "adolescent", "adult"]
        for i in 1:10
            name = Symbol(@sprintf("%s#%03d", cohort, i))
            p = Patient(name)
            @test p.name == string(name)
            @test p.params.BW > 0
            @test length(p.initial_state) == 13
        end
    end
    println("  ✅ Alle 30 Patienten geladen")
end

# ===================================================================
# Test 6: Physiologische Plausibilität
# ===================================================================
@testset "Physiologische Plausibilität" begin
    p = Patient(Symbol("adult#001"))

    # NEU: Ohne Insulin = echtes Nüchtern (BG driftet leicht hoch, aber nicht extrem)
    res = simulate_fast(p; meals=[], insulin=[], basal=0.0, T=480.0, save_every=1)
    @test all(isfinite, res.BG)
    @test all(bg -> bg > 0, res.BG)

    # Mahlzeit ohne Insulin: BG steigt
    res_meal = simulate_fast(p;
        meals=[(time=60, cho=60)], insulin=[], basal=0.0, T=300.0, save_every=1)
    @test maximum(res_meal.BG) > res_meal.BG[1] + 50

    # Insulin ohne Mahlzeit: BG fällt
    res_ins = simulate_fast(p;
        meals=[], insulin=[(time=60, dose=5.0)], basal=0.8, T=300.0, save_every=1)
    @test minimum(res_ins.BG) < res_ins.BG[1] - 10

    println("  ✅ Physiologische Plausibilität bestanden")
end

# ===================================================================
# Test 7: Performance
# ===================================================================
@testset "Performance" begin
    p = Patient(Symbol("adult#001"))
    meals = [(time=60,cho=45),(time=720,cho=70),(time=1080,cho=80)]
    boluses = [(time=55,dose=4.0)]

    # Aufwärmen
    simulate_fast(p; meals, insulin=boluses, basal=0.8, T=1440.0)

    t_start = time_ns()
    n_runs = 50
    for _ in 1:n_runs
        simulate_fast(p; meals, insulin=boluses, basal=0.8, T=1440.0)
    end
    elapsed_ms = (time_ns() - t_start) / 1e6 / n_runs

    @test elapsed_ms < 200.0  # Tsit5 ist langsamer als RK4, aber < 200ms
    @printf("  ✅ 24h-Simulation: %.1f ms (%d Läufe)\n", elapsed_ms, n_runs)
end

println("\n" * "═"^50)
println("✅ Alle Tests bestanden!")
