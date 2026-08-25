"""
    simple_root_matrix(factor::GaugeFactorEmbedding)

Return the exact embedded simple roots as an OSCAR matrix over `QQ`, with one
root per row and 16 columns.
"""
function simple_root_matrix(factor::GaugeFactorEmbedding)
    entries = collect(Iterators.flatten(factor.simple_roots))
    return matrix(QQ, length(factor.simple_roots), 16, entries)
end

"""
    u1_generator_matrix(data::ExactGaugeData)

Return the ordered U(1) generators as an OSCAR matrix over `QQ`, with one
generator per row and 16 columns.
"""
function u1_generator_matrix(data::ExactGaugeData)
    entries = collect(Iterators.flatten(data.u1_generators))
    return matrix(QQ, length(data.u1_generators), 16, entries)
end

"""
    u1_gram_matrix(data::ExactGaugeData)

Return the exact Gram matrix of the embedded U(1) generators. This is a basis
invariant derived from the vectors printed by upstream; no gauge or Higgsing
decision is recomputed in Julia.
"""
function u1_gram_matrix(data::ExactGaugeData)
    generators = u1_generator_matrix(data)
    return generators * transpose(generators)
end

"""
    U1NormalizationData

Exact normalization information intrinsic to the U(1) generator basis printed
by upstream. `gram` contains generator inner products, `dual_gram` is its
inverse and supplies the metric on charge covectors, and `squared_norms` is the
diagonal of `gram`. All values are over `QQ`.

This does not claim a model-classification convention such as a separately
chosen hypercharge length; supported upstream prompts do not print those
optional internal targets.
"""
struct U1NormalizationData{M,T}
    gram::M
    dual_gram::M
    squared_norms::Vector{T}
    orthogonal::Bool
end

"""
    u1_normalization(data::ExactGaugeData) -> U1NormalizationData

Construct exact U(1) basis-normalization data from the 16-dimensional
generators reported by upstream. Linearly dependent generators are rejected
as unsupported output drift.
"""
function u1_normalization(data::ExactGaugeData)
    gram = u1_gram_matrix(data)
    count = length(data.u1_generators)
    rank(gram) == count || error("upstream U(1) generators are linearly dependent")
    dual_gram = count == 0 ? gram : inv(gram)
    squared_norms = [gram[index, index] for index in 1:count]
    orthogonal = all(
        iszero(gram[row, column]) for row in 1:count for column in 1:count if row != column
    )
    return U1NormalizationData(gram, dual_gram, squared_norms, orthogonal)
end

"""
    EmbeddedGaugeFactor

An exact correspondence between one upstream [`GaugeFactorEmbedding`](@ref)
and OSCAR data. `root_system` and `weight_lattice` use the same simple-root
numbering as upstream. `root_lattice` is an OSCAR `ZZLat` whose basis matrix
is the upstream simple roots in the 16-dimensional gauge lattice.

The type parameters are internal OSCAR representation types and should not be
relied upon by callers.
"""
struct EmbeddedGaugeFactor{R,W,L,M}
    source::GaugeFactorEmbedding
    root_system::R
    weight_lattice::W
    root_lattice::L
    fundamental_weights::M
end

"""
    embedded_gauge_factor(factor::GaugeFactorEmbedding) -> EmbeddedGaugeFactor

Construct the OSCAR root system, weight lattice, and the exact 16-dimensional
root- and fundamental-weight embeddings for `factor`. The upstream root Gram
matrix must equal OSCAR's Cartan matrix in the reported order; unrecognized or
drifted output is rejected rather than silently reordered.
"""
function embedded_gauge_factor(factor::GaugeFactorEmbedding)
    family, rank = algebra_to_cartan_type(factor.algebra)
    roots = simple_root_matrix(factor)
    upstream_cartan = roots * transpose(roots)
    expected_cartan = cartan_matrix(family, rank)
    upstream_cartan == expected_cartan || error(
        "simple roots for $(factor.algebra) have Gram matrix different from OSCAR's " *
        "Cartan matrix in upstream order",
    )

    root_system_value = root_system(family, rank)
    weight_lattice_value = weight_lattice(root_system_value)
    rational_cartan = change_base_ring(QQ, expected_cartan)
    fundamental_weights = inv(rational_cartan) * roots
    root_lattice_value = integer_lattice(roots)
    return EmbeddedGaugeFactor(
        factor,
        root_system_value,
        weight_lattice_value,
        root_lattice_value,
        fundamental_weights,
    )
end

"""
    embedded_gauge_factors(data::ExactGaugeData) -> Vector{EmbeddedGaugeFactor}

Construct one embedded OSCAR factor for every non-abelian factor, preserving
the order used by spectrum representations.
"""
embedded_gauge_factors(data::ExactGaugeData) = embedded_gauge_factor.(data.factors)

"""
    fundamental_weight_matrix(factor::EmbeddedGaugeFactor)

Return the exact 16-dimensional fundamental weights as an OSCAR matrix over
`QQ`, one weight per row. Their scalar products with the upstream simple roots
form the identity matrix.
"""
fundamental_weight_matrix(factor::EmbeddedGaugeFactor) = factor.fundamental_weights

"""
    embed_weight(factor::EmbeddedGaugeFactor, weight::WeightLatticeElem)

Map an OSCAR weight associated with `factor.weight_lattice` to its exact
16-dimensional gauge-lattice vector. The returned value is a one-row OSCAR
matrix over `QQ`.
"""
function embed_weight(factor::EmbeddedGaugeFactor, weight::WeightLatticeElem)
    parent(weight) === factor.weight_lattice || throw(
        ArgumentError("weight belongs to a different OSCAR weight lattice"),
    )
    labels = collect(coefficients(weight))
    row = matrix(QQ, 1, length(labels), labels)
    return row * factor.fundamental_weights
end

"""
    GaugeEmbeddingComparison

Exact comparison of gauge embeddings reported by two VEV configurations.
Root positions are `(factor_index, simple_root_index)` pairs. The `*_in_*_span`
fields are basis-independent containment results over `QQ`; shared simple
roots additionally record identical directions, allowing for an overall sign.

U(1) indices refer to the ordered generators in each [`ExactGaugeData`](@ref).
Intersection ranks compare only the non-abelian root spans or only the U(1)
spans. No Higgsing or unbroken-group decision is recomputed.
"""
struct GaugeEmbeddingComparison
    before::ExactGaugeData
    after::ExactGaugeData
    shared_simple_roots::Vector{Tuple{Tuple{Int,Int},Tuple{Int,Int}}}
    before_roots_in_after_span::Vector{Tuple{Int,Int}}
    after_roots_in_before_span::Vector{Tuple{Int,Int}}
    nonabelian_intersection_rank::Int
    before_u1_in_after_span::Vector{Int}
    after_u1_in_before_span::Vector{Int}
    u1_intersection_rank::Int
end
@structural_equality GaugeEmbeddingComparison

function _root_positions_and_vectors(data::ExactGaugeData)
    positions = Tuple{Int,Int}[]
    vectors = Vector{Rational{Int}}[]
    for factor in data.factors
        for (root_index, root) in enumerate(factor.simple_roots)
            push!(positions, (factor.index, root_index))
            push!(vectors, root)
        end
    end
    return positions, vectors
end

function _vector_matrix(vectors::Vector{Vector{Rational{Int}}})
    entries = collect(Iterators.flatten(vectors))
    return matrix(QQ, length(vectors), 16, entries)
end

function _in_row_span(vector::Vector{Rational{Int}}, span_matrix)
    row = matrix(QQ, 1, 16, vector)
    return rank(vcat(span_matrix, row)) == rank(span_matrix)
end

_intersection_rank(left, right) =
    rank(left) + rank(right) - rank(vcat(left, right))

"""
    compare_gauge_embeddings(before::ExactGaugeData, after::ExactGaugeData)
        -> GaugeEmbeddingComparison

Compare two already parsed upstream gauge embeddings using exact rational
linear algebra. Besides exact shared simple roots, report which printed basis
vectors lie in the other configuration's span and the dimensions of the
non-abelian and abelian intersections.
"""
function compare_gauge_embeddings(before::ExactGaugeData, after::ExactGaugeData)
    before_positions, before_roots = _root_positions_and_vectors(before)
    after_positions, after_roots = _root_positions_and_vectors(after)
    before_root_matrix = _vector_matrix(before_roots)
    after_root_matrix = _vector_matrix(after_roots)

    shared = Tuple{Tuple{Int,Int},Tuple{Int,Int}}[]
    for (before_index, before_root) in enumerate(before_roots)
        after_index = findfirst(after_roots) do after_root
            after_root == before_root || after_root == -before_root
        end
        after_index === nothing || push!(
            shared,
            (before_positions[before_index], after_positions[after_index]),
        )
    end
    before_in_after = [
        position for (position, root) in zip(before_positions, before_roots)
        if _in_row_span(root, after_root_matrix)
    ]
    after_in_before = [
        position for (position, root) in zip(after_positions, after_roots)
        if _in_row_span(root, before_root_matrix)
    ]

    before_u1_matrix = u1_generator_matrix(before)
    after_u1_matrix = u1_generator_matrix(after)
    before_u1_in_after = [
        index for (index, generator) in enumerate(before.u1_generators)
        if _in_row_span(generator, after_u1_matrix)
    ]
    after_u1_in_before = [
        index for (index, generator) in enumerate(after.u1_generators)
        if _in_row_span(generator, before_u1_matrix)
    ]
    return GaugeEmbeddingComparison(
        before,
        after,
        shared,
        before_in_after,
        after_in_before,
        _intersection_rank(before_root_matrix, after_root_matrix),
        before_u1_in_after,
        after_u1_in_before,
        _intersection_rank(before_u1_matrix, after_u1_matrix),
    )
end

"""
    compare_gauge_embeddings(model, before, after; timeout = 120)
        -> GaugeEmbeddingComparison

Obtain and compare exact gauge data for two existing upstream configuration
references. Each configuration is selected explicitly in an isolated run.
"""
function compare_gauge_embeddings(
    model::OrbifolderModel,
    before::VEVConfigurationRef,
    after::VEVConfigurationRef;
    timeout::Real = 120,
)
    before_data = compute_exact_gauge_data(model, before; timeout = timeout)
    after_data = compute_exact_gauge_data(model, after; timeout = timeout)
    return compare_gauge_embeddings(before_data, after_data)
end

"""
    compare_gauge_embeddings(model, specification; timeout = 120)
        -> GaugeEmbeddingComparison

Compare the base configuration of a declarative specification with the
derived configuration materialized from it. The derived exact data is read in
the same upstream run in which it is created.
"""
function compare_gauge_embeddings(
    model::OrbifolderModel,
    spec::VEVConfigurationSpec;
    timeout::Real = 120,
)
    before = compute_exact_gauge_data(model, spec.base; timeout = timeout)
    after = compute_exact_gauge_data(model, spec; timeout = timeout)
    return compare_gauge_embeddings(before, after)
end
