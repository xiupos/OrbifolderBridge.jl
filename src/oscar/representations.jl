"""
    dual_weight(R::RootSystem, w::WeightLatticeElem) -> WeightLatticeElem

The highest weight \$-w_0 \\cdot \\lambda\$ of the dual (conjugate)
representation, where \$w_0\$ is the longest element of the Weyl group of
`R`. For self-dual (real/pseudoreal) representations this equals `w` itself.
"""
function dual_weight(R::RootSystem, w::WeightLatticeElem)
    w0 = longest_element(weyl_group(R))
    return -(w * w0)
end

"""
    find_weight_of_dimension(R::RootSystem, dim::Integer; max_coeff::Int = 2) -> WeightLatticeElem

Search for a dominant weight of `R` whose simple module has dimension `dim`,
restricted to Dynkin-label vectors with at most two nonzero entries, each in
`1:max_coeff` (i.e. the trivial weight, single fundamental weights, integer
multiples of a single fundamental weight, and sums of two distinct
fundamental weights). This covers the representations that actually appear
in orbifolder output — (anti)fundamentals, adjoints, vectors, spinors, and
low-order symmetric/antisymmetric tensors — without attempting a fully
general (and, for a bare dimension, ambiguous) inverse of the Weyl dimension
formula.

Throws an `ErrorException` if no such weight is found; the representation
then needs to be specified explicitly by its weight rather than its
dimension.
"""
function find_weight_of_dimension(R::RootSystem, dim::Integer; max_coeff::Int = 2)
    dim >= 1 || throw(ArgumentError("dim must be positive, got $dim"))
    rank = number_of_simple_roots(R)

    dim == 1 && return WeightLatticeElem(R, zeros(Int, rank))

    for i in 1:rank, c in 1:max_coeff
        coeffs = zeros(Int, rank)
        coeffs[i] = c
        w = WeightLatticeElem(R, coeffs)
        dim_of_simple_module(R, w) == dim && return w
    end
    for i in 1:rank, j in (i+1):rank
        coeffs = zeros(Int, rank)
        coeffs[i] = 1
        coeffs[j] = 1
        w = WeightLatticeElem(R, coeffs)
        dim_of_simple_module(R, w) == dim && return w
    end

    error(
        "no dominant weight of rank-$rank root system with dimension $dim found among " *
        "single/double fundamental-weight combinations (max_coeff=$max_coeff); specify the " *
        "representation explicitly by its weight instead of its printed dimension.",
    )
end

"""
    representation_weight(R::RootSystem, rep::Integer) -> WeightLatticeElem

Resolve a single signed representation label as printed in a
[`SpectrumField`](@ref)`.rep` entry (e.g. `10`, `-16`) to a dominant weight of
`R`: the magnitude is matched to a representation dimension via
[`find_weight_of_dimension`](@ref), and a negative sign selects the dual
(conjugate) representation via [`dual_weight`](@ref).
"""
function representation_weight(R::RootSystem, rep::Integer)
    w = find_weight_of_dimension(R, abs(rep))
    return rep < 0 ? dual_weight(R, w) : w
end

"""
    gauge_group_root_systems(gg::GaugeGroup) -> Vector{RootSystem}

Build one `RootSystem` per non-abelian factor of `gg`, in the same
order as `gg.nonabelian` (and hence as [`SpectrumField`](@ref)`.rep`), via
[`algebra_to_cartan_type`](@ref).
"""
function gauge_group_root_systems(gg::GaugeGroup)
    return [root_system(algebra_to_cartan_type(a)...) for a in gg.nonabelian]
end

"""
    field_weights(root_systems::Vector{<:RootSystem}, field::SpectrumField) -> Vector{WeightLatticeElem}

Resolve every entry of `field.rep` to a dominant weight of the corresponding
`root_systems` entry (as returned by [`gauge_group_root_systems`](@ref)), via
[`representation_weight`](@ref).
"""
function field_weights(root_systems::Vector{<:RootSystem}, field::SpectrumField)
    length(root_systems) == length(field.rep) || throw(
        ArgumentError(
            "field.rep has $(length(field.rep)) entries but $(length(root_systems)) root systems were given",
        ),
    )
    return [representation_weight(R, r) for (R, r) in zip(root_systems, field.rep)]
end
