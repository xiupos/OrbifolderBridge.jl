```@meta
CurrentModule = OrbifolderBridge
```

# OSCAR Integration

Parsing and OSCAR construction are separate stages. Spectrum parsing returns
plain Julia values, making it cheap to test and safe to perform after parallel
backend runs. Convert only the data needed for algebraic work.

The examples use `model` from [A first model](@ref). `OrbifolderBridge` already
depends on OSCAR; add `using Oscar` when calling OSCAR operations beyond the
bridge functions shown here.

## Gauge factors as root systems

```julia
spectrum = compute_spectrum(model)
root_systems = gauge_group_root_systems(spectrum.gauge_group)
```

[`algebra_to_cartan_type`](@ref) translates upstream names such as `"SU(3)"`,
`"SO(10)"`, or `"E_6"` into Cartan types. [`gauge_group_root_systems`](@ref)
then constructs one `Oscar.RootSystem` per non-abelian factor, preserving the
order used by `SpectrumField.rep`.

```@docs
algebra_to_cartan_type
gauge_group_root_systems
```

## Exact gauge-lattice embeddings

Upstream can also print the simple roots and U(1) generators in their exact
16-dimensional heterotic gauge-lattice embedding:

```julia
data = compute_exact_gauge_data(model, VEVConfigurationRef("TestConfig1"))
roots = simple_root_matrix(data.factors[1])
generators = u1_generator_matrix(data)
gram = u1_gram_matrix(data)
normalization = u1_normalization(data)

factor = embedded_gauge_factor(data.factors[1])
root_lattice = factor.root_lattice
weight_lattice = factor.weight_lattice
fundamental_weights = fundamental_weight_matrix(factor)
```

The returned [`ExactGaugeData`](@ref) groups roots by the ordered non-abelian
factors and retains observable and hidden factor indices. Its
`anomalous_u1` field identifies the generator explicitly reported as
anomalous by the spectrum summary. Matrix constructors return exact OSCAR
matrices over `QQ`; they do not infer a normalization convention that
upstream does not print.

[`u1_normalization`](@ref) packages the exact Gram matrix, its inverse metric
on charge covectors, the squared generator lengths, and whether the printed
basis is orthogonal. These are intrinsic to the generators and the
16-dimensional lattice inner product used by upstream. Optional target
normalizations used internally by particular model-classification schemes are
not claimed because the prompt does not expose them.

[`embedded_gauge_factor`](@ref) checks that the exact root Gram matrix equals
OSCAR's Cartan matrix in the upstream order. It then constructs an embedded
OSCAR `ZZLat`, the associated abstract `RootSystem` and `WeightLattice`, and
the 16-dimensional fundamental weights. This makes the correspondence of
simple roots and Dynkin-label positions explicit rather than retaining only
the algebra name.

An OSCAR weight from that factor can be returned to the upstream gauge-lattice
basis without losing exactness:

```julia
w = Oscar.fundamental_weight(factor.root_system, 1)
embedded_w = embed_weight(factor, w) # 1 × 16 matrix over QQ
```

## Exact and fallback representation resolution

When exact Dynkin labels are available, connect them to the corresponding
embedded factor and validate the printed dimension:

```julia
resolved = representation_from_dynkin_labels(
    factor,
    [1, 0];
    reported_dimension = 3,
)
resolved.source # :exact_dynkin
```

The supported upstream prompts currently print only signed dimensions. Their
conversion remains available, but its provenance is explicit:

```julia
resolved = resolve_representation(factor, -3)
resolved.source # :dimension_fallback

all_resolved = resolve_field_representations(factors, field)
```

Pass `dynkin_labels` to `resolve_representation` or one label vector per factor
to `resolve_field_representations` to select the exact path. OSCAR's exact
Weyl-dimension calculation must agree with every supplied reported dimension;
a mismatch raises an error. Dimension fallback also rejects dimensions shared
by multiple non-conjugate highest-weight families — `D_4`'s
`8_v`/`8_s`/`8_c` being the case that actually arises. A signed dimension may
select between one conjugate pair, or between `D_6`'s `32`/`32'` and `D_8`'s
`128`/`128'` half-spin pair following upstream's own convention (see
[Representations as highest weights](@ref)), but it is never used to guess
between unrelated representations. Both resolution paths apply the same rule,
so `resolve_representation` and [`representation_weight`](@ref) never disagree
about a printed dimension.

## Comparing VEV configurations

Compare two existing configurations explicitly:

```julia
comparison = compare_gauge_embeddings(
    model,
    VEVConfigurationRef("TestConfig1"),
    VEVConfigurationRef("StandardConfig1"),
)

comparison.shared_simple_roots
comparison.nonabelian_intersection_rank
comparison.before_u1_in_after_span
comparison.u1_intersection_rank
```

For a [`VEVConfigurationSpec`](@ref), the derived exact gauge data is read in
the same isolated process in which the configuration is created:

```julia
spec = VEVConfigurationSpec(
    name = "HiggsConfig1",
    assignments = [VEVAssignment(FieldID(11), 1.0)],
)
comparison = compare_gauge_embeddings(model, spec)
```

The comparison uses exact row spaces over `QQ`, so it recognizes a surviving
subspace even if upstream chooses a different simple-root or U(1) basis. It
also reports identical simple-root directions for direct inspection. These
are comparisons of two upstream results, not a Julia implementation of the
Higgsing decision.

```@docs
GaugeFactorEmbedding
ExactGaugeData
parse_exact_gauge_data
compute_exact_gauge_data
simple_root_matrix
u1_generator_matrix
u1_gram_matrix
U1NormalizationData
u1_normalization
EmbeddedGaugeFactor
embedded_gauge_factor
embedded_gauge_factors
fundamental_weight_matrix
embed_weight
RepresentationWeight
representation_from_dynkin_labels
resolve_representation
resolve_field_representations
GaugeEmbeddingComparison
compare_gauge_embeddings
```

## Representations as highest weights

```julia
field = spectrum.fields[1]
weights = field_weights(root_systems, field)
```

Upstream summary output normally gives signed representation dimensions, not
Dynkin labels. [`representation_weight`](@ref) searches for a dominant weight
with the requested absolute dimension; a negative sign normally selects its
dual via [`dual_weight`](@ref). The exception is `D_6`'s `32`/`32'` and
`D_8`'s `128`/`128'` half-spin representations: both are individually
self-dual, so upstream's sign there does not mean group-theoretic duality but
selects between the two half-spin Dynkin nodes directly, matching upstream's
own hard-coded convention. `D_4`'s triality-related `8_v`/`8_s`/`8_c` share a
single positive printed dimension with no sign distinction at all and remain
ambiguous; supply exact Dynkin labels for that case.

Dimension alone can be ambiguous. [`find_weight_of_dimension`](@ref) therefore
performs a documented bounded search covering the low-weight representations
seen in current fixtures. It raises an error rather than guessing outside that
range. Once upstream exact Dynkin labels or highest weights are exposed, those
should take precedence over dimension inversion.

OSCAR/GAP-backed construction should remain sequential even if spectra were
computed concurrently. See [Consistency and Batch Workflows](@ref) for the
process/parse boundary used by batch APIs.

```@docs
representation_weight
field_weights
find_weight_of_dimension
dual_weight
```
