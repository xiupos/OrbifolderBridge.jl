```@meta
CurrentModule = OrbifolderBridge
```

# Model Classification and Generation

OrbifolderBridge delegates phenomenological classification, random gauge
embedding generation, anomaly tests, and candidate comparison to upstream.
The Julia API describes the requested operation and parses its result; it does
not reproduce upstream's spectrum predicates or selection rules.

## Classifying a model

[`classify_model`](@ref) asks upstream to analyze a VEV configuration for
Standard Model, Pati–Salam, and SU(5) realizations:

```julia
config = VEVConfigurationRef("TestConfig1")
classification = classify_model(model; config = config, generations = 3)
:sm in classification.classes
get(classification.configurations, :sm, String[])
```

The generation count is not a dimension-based Julia heuristic. Upstream
computes the net number of generations and applies its vector-like-exotics
condition. Successful classifications create configuration labels such as
`SMConfig1`, which can be passed to the APIs described in
[VEV Configurations](@ref). The result records the detected backend and
transcript block; an empty `classes` vector is a valid negative classification.

```@docs
ModelClassification
classify_model
```

## Anomaly diagnostics

[`compute_anomaly_report`](@ref) runs upstream's gauge/anomaly analysis and
retains its full diagnostic:

```julia
anomalies = compute_anomaly_report(model; config = config)
anomalies.universal
```

`universal` is true only when upstream explicitly states that all anomaly
ratios are universal. Exact anomalous generators and normalization data belong
to the later exact gauge-data phase; the bridge does not infer them here.

```@docs
AnomalyReport
compute_anomaly_report
```

## Generating candidate models

A generation request explicitly chooses which upstream embedding slots are
inherited. The eight entries are two compactification-shift slots followed by
six Wilson lines. `true` inherits the source entry and `false` asks upstream
to randomize it. non-SUSY keeps its additional Witten shift fixed:

```julia
request = ModelGenerationRequest(;
    count = 10,
    inherit = (true, true, true, true, true, true, false, false),
    classes = [:sm],
    generations = 3,
    inequivalent = true,
)

result = generate_models(model, request; timeout = 600)
result.models
result.diagnostics
```

`generations` requires at least one of `:sm`, `:pati_salam`, or `:su5` because
that is how upstream defines the filter. The upstream programs seed their
random generator from wall-clock time and expose no seed through this command
protocol. A request is therefore not a replayable random stream. The result
instead records the accepted models, request, backend, reported diagnostics,
and a transcript with process identifiers redacted. Use a finite `count`;
upstream's `#models(all)` is intentionally not exposed by this typed API.

### Published upstream examples

The generation requests above map directly to examples in the upstream
manual papers. For example, the non-SUSY Z2×Z4 Standard-Model search is:

```julia
source = only(parse_orbifolder_models(read("modelZ2xZ4_1_6.txt", String); mode = :nonsusy))
request = ModelGenerationRequest(;
    count = 3,
    inherit = ntuple(_ -> false, 8),
    classes = [:sm],
    inequivalent = true,
)
result = generate_models(source, request)
```

Changing `classes` to `[:su5]` gives the published Z3 SU(5) search based on
`modelZ3_1_1.txt`. The SUSY paper likewise uses
`(true, true, false, false, false, false, false, false)` for its Z3 standard
embedding example, and
`(true, true, true, true, true, true, false, false)` with `classes = [:sm]`
for its Z6-II example.

The bridge returns parsed models, so the upstream UI clauses `print info` and
`load when done` have no Julia equivalents. Saving to a temporary model file
and waiting for generation to finish are handled internally. These mappings
are covered using the model files distributed with non-SUSY Orbifolder.

Sources: [The Orbifolder manual paper](https://arxiv.org/abs/1110.5229),
[Non-SUSY Orbifolder](https://arxiv.org/abs/2504.20137).

```@docs
GenerationDiagnostic
ModelGenerationRequest
ModelGenerationResult
generate_models
```

## Selecting inequivalent models

Existing candidates can be filtered independently of generation:

```julia
representatives = select_inequivalent_models(candidates)
```

SUSY 1.2.1 can additionally refine comparison with coupling counts:

```julia
representatives = select_inequivalent_models(
    candidates;
    compare_couplings_through = 4,
)
```

This refinement is absent from non-SUSY 1.0. Requesting it there raises an
error instead of silently falling back to spectrum-only comparison.

```@docs
select_inequivalent_models
```

## Reading upstream model files

Generated and filtered files can contain several `begin model ... end model`
blocks. Parse them into the same model type used by the rest of the bridge:

```julia
models = parse_orbifolder_models(text; mode = :nonsusy)
```

The mode remains explicit because it is not encoded in the upstream file.
Malformed blocks raise an error retaining the complete source text.

```@docs
parse_orbifolder_models
UpstreamModelParseError
```
