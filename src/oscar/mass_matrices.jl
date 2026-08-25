"""
    mass_matrix_polynomial(substitution, result)

Convert a parsed [`MassMatrixResult`](@ref) to an OSCAR matrix over the target
ring of an exact symbolic VEV substitution. Each entry is the sum of its
source-linked VEV monomials; coefficients are one because upstream reports no
exact coupling constants.
"""
function mass_matrix_polynomial(
    substitution::ExactVEVSubstitution,
    result::MassMatrixResult,
)
    values = Any[]
    for i in axes(result.entries, 1), j in axes(result.entries, 2)
        entry = result.entries[i, j]
        value = zero(substitution.target.ring)
        for term in entry
            unknown = filter(
                field -> !haskey(substitution.target.generators, field),
                term.vev_fields,
            )
            isempty(unknown) || throw(ArgumentError(
                "mass-matrix VEV field number $(first(unknown).number) is absent from the target ring",
            ))
            value += prod(
                (substitution.target.generators[field] for field in term.vev_fields);
                init = one(substitution.target.ring),
            )
        end
        push!(values, value)
    end
    return matrix(substitution.target.ring, size(result.entries)..., values)
end

"""
    specialize_mass_matrix(substitution, result, values)

Specialize a symbolic mass matrix at exact rational VEV values and return an
OSCAR matrix over `QQ`. `values` must provide every symbolic VEV field in the
substitution. Numerical floating-point VEVs stored by upstream are not
silently converted to exact coefficients.
"""
function specialize_mass_matrix(
    substitution::ExactVEVSubstitution,
    result::MassMatrixResult,
    values::AbstractDict{FieldID,<:Rational},
)
    missing = filter(field -> !haskey(values, field), substitution.vev_fields)
    isempty(missing) || throw(ArgumentError(
        "no exact value was supplied for VEV field number $(first(missing).number)",
    ))
    extra = filter(field -> !(field in substitution.vev_fields), collect(keys(values)))
    isempty(extra) || throw(ArgumentError(
        "field number $(first(extra).number) is not a VEV variable of the substitution",
    ))
    symbolic = mass_matrix_polynomial(substitution, result)
    images = [
        field in substitution.vev_fields ? QQ(values[field]) : QQ(0)
        for field in substitution.target.fields
    ]
    entries = [
        evaluate(symbolic[i, j], images)
        for i in axes(symbolic, 1), j in axes(symbolic, 2)
    ]
    return matrix(QQ, size(symbolic)..., vec(permutedims(entries)))
end
