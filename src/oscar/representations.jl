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
    for i in 1:rank-1, j in i+1:rank
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

function _weight_candidates_of_dimension(R::RootSystem, dim::Integer; max_coeff::Int = 2)
    rank = number_of_simple_roots(R)
    candidates = WeightLatticeElem[]
    dim == 1 && push!(candidates, WeightLatticeElem(R, zeros(Int, rank)))
    for i in 1:rank, coefficient in 1:max_coeff
        labels = zeros(Int, rank)
        labels[i] = coefficient
        weight = WeightLatticeElem(R, labels)
        dim_of_simple_module(R, weight) == dim && push!(candidates, weight)
    end
    for i in 1:rank-1, j in i+1:rank
        labels = zeros(Int, rank)
        labels[i] = 1
        labels[j] = 1
        weight = WeightLatticeElem(R, labels)
        dim_of_simple_module(R, weight) == dim && push!(candidates, weight)
    end
    return unique(candidates)
end

function _unambiguous_dimension_weight(R::RootSystem, reported::Int)
    # D_6's 32/32' and D_8's 128/128' are two distinct self-dual half-spin
    # representations of the same dimension, so the orbit count below would
    # call them ambiguous. Upstream's sign resolves them, so honour that
    # convention here exactly as `representation_weight` does; anything it
    # does not cover (notably D_4's triality triple) still falls through to
    # the ambiguity rejection.
    special = _d_even_half_spin_weight(R, reported)
    special !== nothing && return special
    candidates = _weight_candidates_of_dimension(R, abs(reported))
    isempty(candidates) && return representation_weight(R, reported)
    orbits = Vector{WeightLatticeElem}[]
    for candidate in candidates
        any(orbit -> candidate in orbit, orbits) && continue
        dual = dual_weight(R, candidate)
        push!(orbits, candidate == dual ? [candidate] : [candidate, dual])
    end
    length(orbits) == 1 || error(
        "reported dimension $reported is ambiguous between $(length(orbits)) " *
        "non-conjugate highest-weight families; supply exact Dynkin labels",
    )
    representative = first(first(orbits))
    return reported < 0 ? dual_weight(R, representative) : representative
end

# If `R` is irreducible of type D_n with n even and n in (6, 8) — the
# half-spin representations upstream's CState::DetermineDimension
# distinguishes by sign despite both being self-dual — return n. Otherwise
# return `nothing`.
#
# D_4's two 8-dimensional half-spin representations share upstream's plain
# positive dimension 8 with the vector representation (triality); upstream
# disambiguates them only through an internal label that the supported
# prompt does not print, so D_4 is intentionally excluded here: no sign
# convention can recover the intended representation from a bare dimension.
function _d_even_half_spin_rank(R::RootSystem)
    types = cartan_type(cartan_matrix(R))
    length(types) == 1 || return nothing
    family, rank = only(types)
    (family === :D && rank in (6, 8)) || return nothing
    return rank
end

# For the D_n (n even) half-spin case identified by `_d_even_half_spin_rank`,
# return the fundamental weight upstream's sign convention selects for the
# signed dimension `rep`, matching CState::DetermineDimension's hard-coded
# D6_32/D6_32bar and D8_128/D8_128bar tables: node n for a positive
# dimension, node n - 1 for the negative one. These two representations are
# each self-dual (`dual_weight` returns the same weight for both, since
# -w_0 = 1 for even D_n), so ordinary duality cannot distinguish upstream's
# positive and negative labels; only this explicit node correspondence can,
# and it relies on `embedded_gauge_factor` having already verified that
# upstream's simple-root numbering matches OSCAR's. Returns `nothing`
# outside this case, or when abs(rep) does not match the half-spin
# dimension.
function _d_even_half_spin_weight(R::RootSystem, rep::Integer)
    rank = _d_even_half_spin_rank(R)
    rank === nothing && return nothing
    spin_dimension = dim_of_simple_module(R, fundamental_weight(R, rank))
    abs(rep) == spin_dimension || return nothing
    return fundamental_weight(R, rep > 0 ? rank : rank - 1)
end

"""
    representation_weight(R::RootSystem, rep::Integer) -> WeightLatticeElem

Resolve a single signed representation label as printed in a
[`SpectrumField`](@ref)`.rep` entry (e.g. `10`, `-16`) to a dominant weight of
`R`: the magnitude is matched to a representation dimension via
[`find_weight_of_dimension`](@ref), and a negative sign selects the dual
(conjugate) representation via [`dual_weight`](@ref).

For `D_6`'s `\\mathbf{32}`/`\\mathbf{32'}` and `D_8`'s
`\\mathbf{128}`/`\\mathbf{128'}` half-spin representations, upstream's sign
does not select the group-theoretic dual — both are individually self-dual —
but the other half-spin node, matching upstream's own hard-coded convention.
`D_4`'s triality-related `\\mathbf{8}_v`/`\\mathbf{8}_s`/`\\mathbf{8}_c` share a
single positive printed dimension with no sign distinction and remain
ambiguous.
"""
function representation_weight(R::RootSystem, rep::Integer)
    special = _d_even_half_spin_weight(R, rep)
    special !== nothing && return special
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

"""
    RepresentationWeight

An OSCAR highest weight together with how it was obtained. `source` is
`:exact_dynkin` when explicit Dynkin labels were supplied and
`:dimension_fallback` when the signed dimension printed by upstream was used.
`reported_dimension` retains that signed upstream value when available.

The type parameter is the internal OSCAR weight representation and should not
be relied upon by callers.
"""
struct RepresentationWeight{W}
    factor_index::Int
    reported_dimension::Union{Nothing,Int}
    weight::W
    source::Symbol
end

"""
    representation_from_dynkin_labels(factor, labels;
                                      reported_dimension = nothing)
        -> RepresentationWeight

Construct an exact OSCAR highest weight from nonnegative Dynkin labels tied to
an [`EmbeddedGaugeFactor`](@ref). If `reported_dimension` is supplied, validate
its magnitude against OSCAR's exact Weyl-dimension calculation.
"""
function representation_from_dynkin_labels(
    factor::EmbeddedGaugeFactor,
    labels::AbstractVector{<:Integer};
    reported_dimension::Union{Nothing,Integer} = nothing,
)
    rank = number_of_simple_roots(factor.root_system)
    length(labels) == rank || throw(ArgumentError(
        "Dynkin label vector has length $(length(labels)), expected rank $rank",
    ))
    all(>=(0), labels) || throw(ArgumentError("highest-weight Dynkin labels must be nonnegative"))
    weight = WeightLatticeElem(factor.root_system, Int.(labels))
    reported = reported_dimension === nothing ? nothing : Int(reported_dimension)
    if reported !== nothing
        actual = dim_of_simple_module(factor.root_system, weight)
        actual == abs(reported) || throw(ArgumentError(
            "reported representation dimension $reported disagrees with exact highest-weight dimension $actual",
        ))
    end
    return RepresentationWeight(factor.source.index, reported, weight, :exact_dynkin)
end

"""
    resolve_representation(factor, reported_dimension; dynkin_labels = nothing)
        -> RepresentationWeight

Prefer exact `dynkin_labels` when supplied. Otherwise invoke the documented
signed-dimension fallback and mark the result with `source ==
:dimension_fallback`. In both cases the returned OSCAR weight is validated
against the reported dimension.
"""
function resolve_representation(
    factor::EmbeddedGaugeFactor,
    reported_dimension::Integer;
    dynkin_labels::Union{Nothing,AbstractVector{<:Integer}} = nothing,
)
    if dynkin_labels !== nothing
        return representation_from_dynkin_labels(
            factor,
            dynkin_labels;
            reported_dimension = reported_dimension,
        )
    end
    reported = Int(reported_dimension)
    weight = _unambiguous_dimension_weight(factor.root_system, reported)
    actual = dim_of_simple_module(factor.root_system, weight)
    actual == abs(reported) || error(
        "dimension fallback produced dimension $actual for reported representation $reported",
    )
    return RepresentationWeight(
        factor.source.index,
        reported,
        weight,
        :dimension_fallback,
    )
end

"""
    resolve_field_representations(factors, field; dynkin_labels = nothing)
        -> Vector{RepresentationWeight}

Resolve every non-abelian representation of `field`. `dynkin_labels`, when
available from an external or future upstream source, must contain one label
vector per factor. Omitting it makes dimension fallback explicit in every
returned result's provenance.
"""
function resolve_field_representations(
    factors::AbstractVector{<:EmbeddedGaugeFactor},
    field::SpectrumField;
    dynkin_labels::Union{Nothing,AbstractVector{<:AbstractVector{<:Integer}}} = nothing,
)
    length(factors) == length(field.rep) || throw(ArgumentError(
        "field.rep has $(length(field.rep)) entries but $(length(factors)) embedded factors were given",
    ))
    dynkin_labels === nothing || length(dynkin_labels) == length(factors) || throw(
        ArgumentError("one Dynkin-label vector is required per gauge factor"),
    )
    return [
        resolve_representation(
            factor,
            representation;
            dynkin_labels = dynkin_labels === nothing ? nothing : dynkin_labels[index],
        )
        for (index, (factor, representation)) in enumerate(zip(factors, field.rep))
    ]
end
