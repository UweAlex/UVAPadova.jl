using UnicodePlots

include("../src/UVAPadova.jl")
using .UVAPadova

# ❗ richtiger Patientenname
p = Patient(Symbol("adult#001"))

res = simulate(p;
    meals=[(time=60.0, cho=45.0)],
    insulin=[(time=55.0, dose=4.0)],
    basal=0.8
)

println("Peak BG: ", maximum(res.BG), " mg/dL")

lineplot(res.t, res.BG,
    title="UVAPadova.jl – adult#001 Test",
    xlabel="min",
    ylabel="BG [mg/dL]")