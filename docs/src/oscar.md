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

## Representations as highest weights

```julia
field = spectrum.fields[1]
weights = field_weights(root_systems, field)
```

Upstream summary output normally gives signed representation dimensions, not
Dynkin labels. [`representation_weight`](@ref) searches for a dominant weight
with the requested absolute dimension; a negative sign selects its dual via
[`dual_weight`](@ref).

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
