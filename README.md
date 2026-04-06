# UVAPadova.jl

High-performance, differentiable Julia implementation of the UVA/Padova S2008 Glucose-Insulin Model — a modern, full-featured replacement for simglucose and the central plasma dynamics generator for the T1D-Dosis.jl project (ICT / Pen injections only).

## Project Goals

UVAPadova.jl fulfills two roles at the same time:

1. Standalone Project  
   A faster, cleaner, and significantly more powerful replacement for the Python package simglucose. Numerically nearly identical, but with much better performance, full differentiability (ForwardDiff), and a modern Julia architecture.

2. Building Block for the T1D-Dosis.jl Masterplan  
   Provides stable plasma dynamics (gastric emptying, endogenous glucose production, nonlinear insulin action, tissue glucose, etc.) for pure ICT/pen injection scenarios.  
   MDI-specific effects (realistic pen depot kinetics, variable absorption, exercise-induced depot acceleration, fat/protein delays) are complemented by the LT1 model.

## Validation Results

Both solvers were validated against 366 simglucose reference datasets:

| Solver                | Mean MAE   | Max Error  | ForwardDiff Compatible | Primary Use Case                  |
|-----------------------|------------|------------|------------------------|-----------------------------------|
| simulate (Reference)  | 1.78 mg/dL | 71.5 mg/dL | No                     | Validation & reference generation |
| simulate_fast (AD)    | 2.31 mg/dL | 114 mg/dL  | Yes                    | Parameter optimization & gradients|

Note on Max Error: The largest deviations occur exclusively in the extreme case child#008_high_carb. In this scenario, a lightweight child receives a very large bolus, causing an extremely steep glucose peak. The error is caused by slight differences in sampling timing between simglucose and Julia. The mean MAE for this patient is only 4.6 mg/dL. This is a sampling artifact, not a model error.

## The 366 Reference Datasets

The reference data in data/reference/ is a valuable asset of this project. It was generated once with simglucose and enables full validation without any Python dependency.

### Standard Tests (90 datasets)

30 virtual patients × 3 clinical scenarios, each covering 24 hours:

| Scenario      | Meals                                      | Boluses             | Basal Rate |
|---------------|--------------------------------------------|---------------------|------------|
| standard_day  | 5 meals (45g, 70g, 15g, 80g, 10g)         | 1 × 4 U             | 0.8 U/min  |
| high_carb     | 3 large meals (80g, 110g, 90g)            | 2 × (6 U + 8 U)     | 1.2 U/min  |
| low_carb      | 3 small meals (30g, 40g, 25g)             | 1 × 2 U             | 0.6 U/min  |

These scenarios cover typical daily life: normal day, high-carb situations, and low-carb diet.

### Perturbation Tests (276 datasets)

46 model parameters × 6 multipliers (0.90, 0.95, 0.99, 1.01, 1.05, 1.10) based on adult#001_standard_day.

Key insight: 12 parameters show no measurable effect on BG when changed by ±10 %. The strongest sensitivity is shown by kp1, Vg, and f.

## Installation

    using Pkg
    Pkg.activate(".")
    Pkg.instantiate()

## Quick Start

    include("src/patients.jl")
    include("src/model.jl")
    include("src/fast.jl")

    p = Patient(Symbol("adult#001"))

    # Fast, AD-compatible simulation
    res = simulate_fast(p;
        meals   = [(time=60, cho=45), (time=720, cho=70)],
        insulin = [(time=55, dose=4.0)],
        basal   = 0.8,
        T       = 1440.0)

    # Result: res.t (time points), res.BG (blood glucose in mg/dL)

## Two Solvers

### simulate_fast — Recommended for most use cases

Segment-wise Tsit5 integration. Stops at each meal start to read gastric content for Dbar, then continues with a new segment. No mutable state, no callbacks.

- Mathematically very accurate (Tsit5, tol 1e-8)
- Fully ForwardDiff compatible
- Very fast (~10–50 ms for 24 h simulation)
- Mean MAE 2.31 mg/dL vs simglucose

### simulate — Reference Mode

DiffEq solver with PresetTimeCallbacks for exact Dbar tracking.

- Mean MAE 1.78 mg/dL vs simglucose
- Used primarily for validation

### simulate_with_θ — For Optimization

    using ForwardDiff

    param_names = (:kp1, :Vmx, :ki)
    θ = [p.params.kp1, p.params.Vmx, p.params.ki]

    J = ForwardDiff.jacobian(θ -> simulate_with_θ(p, θ, param_names; ...), θ)

## Model

UVA/Padova S2008 with 13 state variables:

| #  | Variable | Description                        |
|----|----------|------------------------------------|
| 1  | qsto1    | Stomach solid phase                |
| 2  | qsto2    | Stomach liquid phase               |
| 3  | qgut     | Gut                                |
| 4  | Gp       | Plasma glucose                     |
| 5  | Gt       | Tissue glucose                     |
| 6  | Ip       | Plasma insulin                     |
| 7  | X        | Insulin action                     |
| 8  | Xl       | Delayed insulin action 1           |
| 9  | Id       | Delayed insulin action 2           |
| 10 | Il       | Liver insulin                      |
| 11 | Isc1     | Subcutaneous insulin, compartment 1|
| 12 | Isc2     | Subcutaneous insulin, compartment 2|
| 13 | Gs       | Subcutaneous glucose (CGM)         |

## Virtual Patients

30 virtual patients from data/vpatient_params.csv (identical to simglucose):

- child#001 to child#010
- adolescent#001 to adolescent#010
- adult#001 to adult#010

## Tests

### Unit Tests

    julia --project test/runtests.jl

### Full Validation against simglucose

    julia validate.jl

Results are saved to data/validation_results.csv. No Python required.

## Project Structure

    UVAPadova.jl/
    ├── src/
    │   ├── UVAPadova.jl
    │   ├── patients.jl
    │   ├── model.jl
    │   └── fast.jl
    ├── test/
    ├── data/
    │   ├── vpatient_params.csv
    │   ├── reference/
    │   └── validation_results.csv
    ├── validate.jl
    ├── generate_reference.jl
    ├── Project.toml
    └── README.md

## Dependencies

Core (Simulation + AD):  
StaticArrays, DifferentialEquations, ForwardDiff, CSV, DataFrames

Optional (for reference data generation):  
PythonCall, CondaPkg (Python + simglucose)

## References

- Dalla Man C, Rizza RA, Cobelli C. Meal simulation model of the glucose-insulin system. IEEE Trans Biomed Eng. 2007.
- Dalla Man C et al. The UVA/PADOVA Type 1 Diabetes Simulator: New Features. J Diabetes Sci Technol. 2014.
- Xie J. simglucose v0.2.1. 2018.
- Eichenlaub M et al. LoopInsighT1 (LT1).

---

License: MIT License . The UVA/Padova model is based on published equations. Virtual patient parameters are taken from simglucose (MIT License).

