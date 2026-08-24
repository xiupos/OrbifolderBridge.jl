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

```@docs
compute_gauge_sector
parse_gauge_sector
GaugeSector
```

## Current mutation boundary

Configuration creation, numerical VEV assignment, and recomputation of the
unbroken gauge group remain available through [`run_orbifolder_script`](@ref)
while their reproducible typed protocol is investigated. In particular,
upstream's random VEV option has no controllable seed and is unsuitable as a
default high-level operation.
