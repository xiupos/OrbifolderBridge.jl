"""
    CouplingPolynomialRing

An OSCAR polynomial ring over `QQ` with one generator for every stable field
identity in `fields`. Generator names are `f_<field number>` and
`generators[field]` provides the bijection back to [`FieldID`](@ref).
"""
struct CouplingPolynomialRing{RingT,ElemT}
    ring::RingT
    fields::Vector{FieldID}
    generators::Dict{FieldID,ElemT}
end
@structural_equality CouplingPolynomialRing

"""
    ExactVEVSubstitution

An exact OSCAR ring homomorphism replacing each field in `vev_fields` by a
target-ring generator named `v_<field number>`. Other generators retain their
`f_<field number>` names. VEV magnitudes are symbolic and exact; upstream's
floating-point numerical VEV storage is intentionally not folded into this
map.
"""
struct ExactVEVSubstitution{SourceT,TargetT,MapT}
    source::SourceT
    target::TargetT
    vev_fields::Vector{FieldID}
    homomorphism::MapT
end

"""
    EffectiveCouplingPolynomial

One source [`CouplingTerm`](@ref) together with its image under an
[`ExactVEVSubstitution`](@ref). Keeping one value per source term preserves
provenance even when several terms have the same effective polynomial.
"""
struct EffectiveCouplingPolynomial{ElemT}
    source::CouplingTerm
    polynomial::ElemT
    vev_fields::Vector{FieldID}
end
@structural_equality EffectiveCouplingPolynomial

"""
    coupling_polynomial_ring(fields) -> CouplingPolynomialRing

Construct the canonical exact polynomial ring for `fields`. Input order does
not affect the result; fields are ordered by their zero-based upstream number.
"""
function coupling_polynomial_ring(fields::AbstractVector{FieldID})
    isempty(fields) && throw(ArgumentError("at least one field is required"))
    unique_fields = unique(fields)
    length(unique_fields) == length(fields) ||
        throw(ArgumentError("fields must not contain duplicates"))
    sort!(unique_fields; by = field -> field.number)
    ring, values = polynomial_ring(QQ, ["f_$(field.number)" for field in unique_fields])
    return CouplingPolynomialRing(
        ring,
        unique_fields,
        Dict(field => value for (field, value) in zip(unique_fields, values)),
    )
end

function coupling_polynomial_ring(terms::AbstractVector{CouplingTerm})
    fields = reduce(vcat, (term.fields for term in terms); init = FieldID[])
    return coupling_polynomial_ring(unique(fields))
end

coupling_polynomial_ring(result::Union{CouplingResult,CouplingSearchResult}) =
    coupling_polynomial_ring(result.terms)

"""
    coupling_polynomial(data, coupling)

Convert a coupling term, a vector of terms, or a coupling result to the OSCAR
polynomial ring in `data`. A vector/result is represented by the sum of its
monomials. Upstream reports allowed monomials rather than exact numerical
coupling strengths, so every term has coefficient one.
"""
function coupling_polynomial(data::CouplingPolynomialRing, term::CouplingTerm)
    unknown = filter(field -> !haskey(data.generators, field), term.fields)
    isempty(unknown) || throw(ArgumentError(
        "coupling refers to field number $(first(unknown).number) absent from the polynomial ring",
    ))
    return prod((data.generators[field] for field in term.fields); init = one(data.ring))
end

function coupling_polynomial(
    data::CouplingPolynomialRing,
    terms::AbstractVector{CouplingTerm},
)
    return sum((coupling_polynomial(data, term) for term in terms); init = zero(data.ring))
end

coupling_polynomial(
    data::CouplingPolynomialRing,
    result::Union{CouplingResult,CouplingSearchResult},
) = coupling_polynomial(data, result.terms)

"""
    exact_vev_substitution(source, vev_fields) -> ExactVEVSubstitution

Construct the exact symbolic VEV-substitution homomorphism for a coupling
ring. Every requested VEV field must be a generator of `source`.
"""
function exact_vev_substitution(
    source::CouplingPolynomialRing,
    vev_fields::AbstractVector{FieldID},
)
    fields = collect(vev_fields)
    length(unique(fields)) == length(fields) ||
        throw(ArgumentError("vev_fields must not contain duplicates"))
    unknown = filter(field -> !haskey(source.generators, field), fields)
    isempty(unknown) || throw(ArgumentError(
        "VEV field number $(first(unknown).number) is absent from the source ring",
    ))
    vev_set = Set(fields)
    names = [
        field in vev_set ? "v_$(field.number)" : "f_$(field.number)"
        for field in source.fields
    ]
    target_ring, target_values = polynomial_ring(QQ, names)
    target = CouplingPolynomialRing(
        target_ring,
        copy(source.fields),
        Dict(field => value for (field, value) in zip(source.fields, target_values)),
    )
    images = [target.generators[field] for field in source.fields]
    return ExactVEVSubstitution(
        source,
        target,
        sort!(fields; by = field -> field.number),
        hom(source.ring, target.ring, images),
    )
end

"""
    apply_vev_substitution(substitution, coupling)

Apply an exact symbolic VEV substitution to a polynomial, one coupling term,
or a vector/result of coupling terms. Term-based overloads retain each source
term in [`EffectiveCouplingPolynomial`](@ref).
"""
apply_vev_substitution(substitution::ExactVEVSubstitution, polynomial) =
    substitution.homomorphism(polynomial)

function apply_vev_substitution(
    substitution::ExactVEVSubstitution,
    term::CouplingTerm,
)
    polynomial = coupling_polynomial(substitution.source, term)
    return EffectiveCouplingPolynomial(
        term,
        substitution.homomorphism(polynomial),
        copy(substitution.vev_fields),
    )
end

apply_vev_substitution(
    substitution::ExactVEVSubstitution,
    terms::AbstractVector{CouplingTerm},
) = [apply_vev_substitution(substitution, term) for term in terms]

apply_vev_substitution(
    substitution::ExactVEVSubstitution,
    result::Union{CouplingResult,CouplingSearchResult},
) = apply_vev_substitution(substitution, result.terms)
