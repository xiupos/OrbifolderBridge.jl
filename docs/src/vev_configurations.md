```@meta
CurrentModule = OrbifolderBridge
```

# VEV Configurations

Upstream evaluates spectra, gauge groups, anomaly information, and model
classification in a selected VEV configuration. OrbifolderBridge represents
that choice explicitly instead of relying on the upstream prompt's mutable
current state.

The examples use `model` from [A first model](@ref).

## Listing configurations

Loading a model normally creates `StandardConfig1` and `TestConfig1`. Ask
upstream for the actual list rather than assuming those names:

```julia
configs = list_vev_configurations(model)

for config in configs
    println(config.configuration.label, config.selected ? " (selected)" : "")
end
```

[`VEVConfigurationSummary`](@ref) also records the active field-label scheme
and labels of fields with VEVs when upstream prints them. `print configs` does
not report numerical VEV values, so the bridge does not infer them.

```@docs
list_vev_configurations
parse_vev_configurations
VEVConfigurationSummary
```

## Selecting a configuration explicitly

Construct a reference from a returned label and pass it to each
configuration-dependent operation:

```julia
standard = VEVConfigurationRef("StandardConfig1")

group = compute_gauge_group(model, standard)
spectrum = compute_spectrum(model, standard)
detailed = compute_detailed_spectrum(model, standard)
```

Each operation issues `use config(StandardConfig1)` in its own isolated
upstream process and verifies the acknowledgement before parsing. An unknown
configuration raises [`VEVConfigurationError`](@ref), retaining the raw
transcript for diagnosis.

The overloads without a configuration remain for backwards compatibility.
They use the backend's initial selection and should be avoided in reproducible
workflows. Classification and anomaly analysis use a keyword:

```julia
classification = classify_model(model; config = standard)
anomalies = compute_anomaly_report(model; config = standard)
```

The parallel spectrum and gauge-group APIs accept the reference as their
second argument.

```@docs
VEVConfigurationRef
VEVConfigurationError
```

## Observable and hidden sectors

Upstream encloses hidden factors in brackets. The bridge preserves that
selection as factor indices rather than embedding brackets in algebra names:

```julia
sector = compute_gauge_sector(model, standard)

sector.gauge_group.nonabelian
sector.observable_nonabelian
sector.hidden_nonabelian
sector.observable_u1
sector.hidden_u1
```

Indices are one-based and refer to the factor order in `gauge_group`. The
bridge reports upstream's partition; it does not choose an observable sector.

Use [`compare_gauge_embeddings`](@ref) when the exact change of non-abelian
root and U(1) spans matters. It accepts two existing configuration references
or a replayable [`VEVConfigurationSpec`](@ref) and compares only the gauge
embeddings reported by upstream.

```@docs
compute_gauge_sector
parse_gauge_sector
GaugeSector
```

## Building a derived configuration

A [`VEVConfigurationSpec`](@ref) describes how to reconstruct a derived
configuration in every isolated upstream process:

```julia
spec = VEVConfigurationSpec(
    name = "VisibleConfig1",
    base = standard,
    observable_nonabelian = [1, 2],
    observable_u1 = [1],
)

result = materialize_vev_configuration(model, spec)
result.gauge_sector
result.spectrum
```

`nothing` preserves the base observable-sector choice, while an empty vector
selects no factors of that kind. Factor indices are checked against the base
configuration before mutation. The requested name must not collide with a
configuration created when the model is loaded.

A spec may be passed anywhere a derived configuration must be replayed:

```julia
compute_spectrum(model, spec)
compute_gauge_group(model, spec)
classify_model(model; config = spec)
compute_anomaly_report(model; config = spec)
```

If the spec hides a non-abelian factor, upstream folds that factor's
representation dimension into grouped multiplicities. There is then no
unambiguous one-to-one detailed spectrum, so
`result.detailed_spectrum === nothing` and `compute_detailed_spectrum` rejects
the request instead of returning misleading field multiplicities.

```@docs
VEVConfigurationSpec
VEVConfigurationResult
materialize_vev_configuration
```

## Assigning fixed VEVs

SUSY orbifolder 1.2.1 supports deterministic fixed VEV assignments and
unbroken gauge-group recomputation. In the following example, `susy_model` is
an [`OrbifolderModel`](@ref) with `mode = :susy`:

```julia
vev_spec = VEVConfigurationSpec(
    name = "SingletVEV1",
    base = VEVConfigurationRef("TestConfig1"),
    assignments = [VEVAssignment(FieldID(11), 1.0)],
)

vacuum = materialize_vev_configuration(susy_model, vev_spec)
vacuum.assignments
vacuum.gauge_sector
vacuum.spectrum
```

The bridge first resolves each stable `FieldID` to the active label in the
base configuration, then creates the derived configuration, assigns fixed
values, asks upstream to identify the unbroken group, and reads the VEVs back
from internal field information. Both upstream transcripts are retained.

Upstream exposes no weight-component selector, so the typed API initially
accepts only fields that are singlets under every non-abelian factor. Random
VEVs are deliberately excluded because upstream provides no controllable
seed. nonSUSYorbifolder supports configuration derivation and observable
sector selection but rejects nonempty VEV assignments and unbroken-group
recomputation through typed capability checks.

```@docs
VEVAssignment
FieldVEV
parse_field_vevs
```
