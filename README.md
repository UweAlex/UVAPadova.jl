
# UVAPadova.jl

Hochperformante, differenzierbare Julia-Implementierung des UVA/Padova S2008 Glukose-Insulin-Modells  
– vollwertiger, moderner Ersatz für simglucose und zentraler Plasma-Generator für das T1D-Dosis.jl Masterplan (ICT / Pen-Injektionen).

## Ziel des Projekts

UVAPadova.jl erfüllt zwei Rollen gleichzeitig:

1. Eigenständiges Projekt  
   Schneller, sauberer und deutlich leistungsfähiger Ersatz für das Python-Paket simglucose. Numerisch praktisch identisch, aber mit deutlich besserer Geschwindigkeit, vollständiger Differenzierbarkeit und moderner Julia-Architektur.

2. Baustein für das T1D-Dosis.jl Masterplan  
   Liefert die stabile Plasmadynamik (Magenentleerung, endogene Glukoseproduktion, nichtlineare Insulinwirkung, Gewebe-Glukose etc.) für reine ICT/Pen-Injektions-Szenarien.  
   Die MDI-spezifischen Effekte (realistisches Pen-Depot, variable Absorption, Exercise-Einfluss auf das Depot, Fat/Protein-Verzögerung) werden komplementär durch das LT1-Modul abgedeckt.

## Validierungsergebnis

| Metrik                  | Standard-Tests (90) | Perturbation-Tests (276) |
|-------------------------|---------------------|--------------------------|
| Mittlere MAE            | 1.78 mg/dL          | 1.65 mg/dL               |
| Max Error               | 71.5 mg/dL          | 21.3 mg/dL               |
| Tests bestanden         | 90/90               | 276/276                  |

366 Tests über 30 virtuelle Patienten (10 Kinder, 10 Jugendliche, 10 Erwachsene) und 3 Szenarien – alles gegen simglucose validiert.

## Installation

    using Pkg
    Pkg.activate(".")
    Pkg.instantiate()

## Schnellstart

    using UVAPadova

    # Patient laden
    p = Patient(Symbol("adult#001"))

    # Empfohlene schnelle Simulation (AD-kompatibel)
    res = simulate_fast(p;
        meals   = [(time=60, cho=45), (time=720, cho=70)],
        insulin = [(time=55, dose=4.0)],
        basal   = 0.8,
        T       = 1440.0)

    # Ergebnis
    println("BG-Werte: ", res.BG[1:5], " …")

## Zwei Solver

### simulate_fast() – Standard für die meisten Anwendungen
- Segment-weiser Tsit5-Solver
- Vollständig ForwardDiff-kompatibel
- Sehr schnell und deterministisch
- Ideal für Parameter-Fitting (Levenberg–Marquardt)

### simulate() – Referenz-Modus (DiffEq + Callbacks)
- Exakte Nachbildung des simglucose-Verhaltens
- Wird primär für Validierung verwendet

### simulate_with_θ() – Direkt für Optimierung

    using ForwardDiff
    θ = [p.params.kp1, p.params.Vmx]
    J = ForwardDiff.jacobian(θ -> simulate_with_θ(p, θ, (:kp1, :Vmx); ...), θ)

## Modell

UVA/Padova S2008 mit 13 Zustandsvariablen.  
Das Modell ist hervorragend geeignet für die stabile Plasmadynamik bei Pen-Injektionen. Die grundlegende subkutane Insulin-Kinetik ist enthalten, aber für höchste Realität bei ICT-Szenarien wird es bewusst mit dem LT1-Modul kombiniert (Pen-Depot-Effekte).

## Patienten

30 virtuelle Patienten (identisch mit simglucose) aus data/vpatient_params.csv:
- child#001–010
- adolescent#001–010
- adult#001–010

## Tests & Validierung

    # Unit-Tests (Smoke, AD, Performance, Plausibilität)
    julia --project test/runtests.jl

    # Vollständige Validierung gegen simglucose-Referenzdaten
    julia validate.jl

## Projektstruktur

    UVAPadova.jl/
    ├── src/
    │   ├── UVAPadova.jl
    │   ├── patients.jl
    │   ├── model.jl          # Referenz-Solver
    │   └── fast.jl           # AD-kompatibler Solver
    ├── test/
    ├── data/
    │   ├── vpatient_params.csv
    │   └── reference/        # 366 simglucose-Referenz-CSVs
    ├── validate.jl
    ├── generate_reference.jl
    └── README.md

## Abhängigkeiten

Kern:  
StaticArrays, DifferentialEquations, ForwardDiff, CSV, DataFrames

Nur für Referenz-Generierung (optional):  
PythonCall + simglucose

## Referenzen

- Dalla Man et al. (2007) – Meal Simulation Model of the Glucose-Insulin System
- Xie J. – simglucose v0.2.1
- Masterplan T1D-Dosis.jl (UVA2008 als Plasma-Generator + LT1 für MDI-spezifische Effekte)

---

Lizenz: Forschungszwecke (basierend auf publizierten Gleichungen und simglucose MIT-Lizenz).
