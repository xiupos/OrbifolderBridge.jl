```@meta
CurrentModule = OrbifolderBridge
```

# Integrated and Reproducible Analysis

Use [`analyze`](@ref) when related results must come from the same upstream
process, selected VEV configuration, and field basis:

```julia
result = analyze(
    model;
    config = VEVConfigurationRef("TestConfig1"),
    include = [
        :detailed_spectrum,
        :exact_gauge_data,
        :space_group_metadata,
        :localizations,
    ],
)

result.detailed_spectrum
result.exact_gauge_data
result.localizations
```

Supported items are `:gauge_group`, `:spectrum`, `:detailed_spectrum`,
`:exact_gauge_data`, `:twist`, `:shift_vectors`, `:wilson_lines`,
`:space_group_metadata`, and `:localizations`. Dependencies are returned as
well as reused: requesting exact gauge data also populates `gauge_group` and
`spectrum`; requesting localizations also populates `detailed_spectrum` and
`spectrum`. Unrequested independent fields are `nothing`.

The command planner prints each dependency once. It does not include coupling
generation, effective superpotentials, mass matrices, random model generation,
or materialization of a [`VEVConfigurationSpec`](@ref). Those operations have
stateful child-process or artifact protocols and remain available through
their dedicated APIs.

## Computation context

A context fixes the complete execution scope before the run:

```julia
context = ComputationContext(
    model;
    config = VEVConfigurationRef("TestConfig1"),
    timeout = 120,
)
result = analyze(context; include = [:spectrum, :twist])
```

It validates the configured backend and requires its kind to match the model.
As with the smaller computation APIs, omitting `config` retains the backend's
initial configuration for compatibility; reproducible analyses should select
one explicitly.

```@docs
ComputationContext
analyze
AnalysisResult
```

## Provenance and diagnostics

Every result has one [`AnalysisProvenance`](@ref), containing:

- detected backend kind, version, paths, and capabilities;
- SHA-256 of the exact text returned by [`model_file_text`](@ref);
- the selected Geometry filename and SHA-256 of its contents;
- the explicit VEV configuration;
- the complete normalized command sequence;
- unique warning lines reported by upstream;
- the complete raw transcript.

The Geometry digest detects a changed definition even when its filename stays
the same. An [`AnalysisParseError`](@ref) identifies the failed result item and
retains the complete transcript rather than only the command block.

```@docs
GeometryIdentity
AnalysisProvenance
AnalysisParseError
```

## Integrated batches

```julia
results = analyze_batch(
    models;
    config = VEVConfigurationRef("TestConfig1"),
    include = [:detailed_spectrum, :exact_gauge_data],
    ntasks = 8,
)
```

Each model receives one independent temporary directory and one upstream
process. Executions run concurrently, results retain input order, and parsing
occurs after execution. OSCAR/GAP constructions should still be performed
sequentially by callers.

```@docs
analyze_batch
```
