using CSV, DataFrames, StaticArrays

Base.@kwdef struct UVAPatientParams{T<:Real}
    BW::T
    kabs::T
    kmax::T
    kmin::T
    b::T
    d::T
    f::T
    Vg::T
    Vm0::T
    Vmx::T
    Km0::T
    k1::T
    k2::T
    Fsnc::T
    ke1::T
    ke2::T
    kp1::T
    kp2::T
    kp3::T
    ki::T
    Vi::T
    Ib::T
    m1::T
    m2::T
    m4::T
    m30::T
    p2u::T
    ka1::T
    ka2::T
    kd::T
    ksc::T
    EGPb::T
    Gb::T
    Gpb::T
    Gtb::T
    Ipb::T
    Ilb::T
    u2ss::T
end

struct Patient
    name::String
    params::UVAPatientParams
    initial_state::MVector{13,Float64}
end