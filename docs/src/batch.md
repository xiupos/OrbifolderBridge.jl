```@meta
CurrentModule = OrbifolderBridge
```

# Consistency and Batch Workflows

Model scans should reject inconsistent inputs before launching more expensive
spectrum calculations. OrbifolderBridge delegates that decision to upstream
and keeps process failures distinct from physical rejection.

The single-model example uses `model` from [A first model](@ref). In the batch
examples, `models` denotes a vector of `OrbifolderModel` values with distinct
labels.

## Checking one model

```julia
result = check_consistency(model)

if result.valid
    spectrum = compute_spectrum(model)
else
    @warn result.message
end
```

A [`ConsistencyResult`](@ref) with `valid == false` means the backend emitted a
recognized model-rejection diagnostic. It retains the raw transcript for
inspection. Missing binaries, invalid Geometry configuration, timeouts,
process crashes, and unknown output formats remain exceptions.

For a Boolean-only check, `OrbifolderBridge.is_consistent(model)` is a
convenience wrapper around `check_consistency(model).valid`. The qualification
is useful because OSCAR also exports a function named `is_consistent`; an
unqualified call is ambiguous after both packages have been brought into scope
with `using`.

```@docs
ConsistencyResult
check_consistency
is_consistent
```

## Filtering a collection

```julia
results = check_consistency_batch(models; ntasks = 8)

valid_models = [
    model for (model, result) in zip(models, results) if result.valid
]
```

[`partition_consistent_models`](@ref) returns the valid and invalid subsets in
input order when both are needed.

```@docs
check_consistency_batch
partition_consistent_models
```

## Computing many results

```julia
spectra = compute_spectra(valid_models; ntasks = 8)
groups = compute_gauge_groups(valid_models; ntasks = 8)
```

Batch operations use independent temporary directories and launch backend
processes concurrently. Results remain in input order. Plain transcript
parsing happens after the process runs; callers should construct OSCAR/GAP
objects sequentially because those libraries are not assumed thread-safe.

The available batch functions mirror the inexpensive single-model operations.
Detailed spectra currently use the single-model API because their upstream
transcripts are substantially larger.

```@docs
compute_spectra
compute_gauge_groups
compute_twists
compute_shift_vectors_batch
compute_wilson_lines_batch
```
