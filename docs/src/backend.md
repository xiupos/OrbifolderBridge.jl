```@meta
CurrentModule = OrbifolderBridge
```

# Backend Configuration

Every public computation ultimately launches one of the two upstream
executables in an isolated temporary directory. The executables and their
`Geometry/` directories come from the `OrbiFolder_jll`/`NonSUSYOrbiFolder_jll`
dependencies. The remaining functions on this page are escape hatches and
parser building blocks.

## Locating binaries and Geometry data

[`orbifolder_binary`](@ref) returns the JLL executable and
[`orbifolder_geometry_dir`](@ref) returns the `Geometry/` directory bundled in the
same artifact. OrbifolderBridge supports Linux only; see [Upstream Notes](@ref).

[`backend_info`](@ref) runs the backend through its real isolated batch
protocol and reads the kind and version from the startup banner:

```julia
info = backend_info(:susy)
info.kind       # :susy
info.version    # v"1.2.1"
```

OrbifolderBridge currently supports `orbifolder` 1.2.1 and
`nonSUSYorbifolder` 1.0. Unknown kinds and versions raise
[`BackendCompatibilityError`](@ref) instead of allowing a parser to return
partial data. Every typed computation and raw script performs this preflight
check.

A successful probe is cached per mode, so a computation launches the backend
once rather than twice; `refresh = true` forces a new probe.

```@docs
orbifolder_binary
orbifolder_geometry_dir
BackendInfo
BackendCompatibilityError
backend_info
```

## Capabilities and self-test

Capabilities describe operations supported by the bridge for the detected
kind/version pair. They are symbols intended for feature checks rather than
version comparisons:

```julia
info = backend_info(:nonsusy)
supports(info, :detailed_spectrum)       # true
supports(info, :couplings)               # false: no non-SUSY coupling engine
```

The capability set also records backend-specific differences. In particular,
`:coupling_refined_inequivalence` is available for SUSY 1.2.1 but not
non-SUSY 1.0. Both backends advertise `:vev_configuration_mutation`, while
`:field_vevs` and `:unbroken_gauge_group` are SUSY-only capabilities.
`:couplings` and `:mass_matrices` are likewise SUSY-only because the supported
non-SUSY command tree has no corresponding implementation.

For setup diagnostics, [`check_backend`](@ref) catches configuration,
execution, timeout, and compatibility failures and returns a
[`BackendSelfTest`](@ref). A false result carries a human-readable `message`
and any output captured before the failure:

```julia
result = check_backend(:susy)
result.ok || @warn result.message
```

This check is deliberately lightweight: it completes the backend's normal
script protocol without loading a physical model. Being a diagnostic, it always
re-probes the executable instead of reusing a cached [`backend_info`](@ref).

```@docs
supports
BackendSelfTest
check_backend
```

## Raw command scripts

[`run_orbifolder_script`](@ref) is the supported low-level escape hatch for an
upstream feature that has no typed API yet:

```julia
transcript = run_orbifolder_script(
    :nonsusy,
    ["load orbifolds(model.txt)", "cd $(model.label)", "cd spectrum", "print summary"];
    files = Dict("model.txt" => model_file_text(model)),
)
```

Here `model` is the value constructed in [A first model](@ref).

It hides the different SUSY and non-SUSY batch protocols, applies a timeout,
stages Geometry data, and returns the raw transcript. It deliberately does not
expose the upstream prompt as a Julia session API.

```@docs
run_orbifolder_script
run_capture
```

## Parsing transcripts

[`split_transcript`](@ref) separates the response by echoed command and
[`output_for`](@ref) selects one command's output. The `parse_*` functions turn
captured output into plain Julia values. They are useful when developing a new
typed operation; ordinary callers should prefer `compute_*`.

```@docs
split_transcript
output_for
parse_rational
parse_rational_vector
parse_gauge_group
parse_spectrum
parse_detailed_spectrum
parse_twist
parse_shift_vectors
parse_wilson_lines
```

## Process errors

Backend timeouts, nonzero exits, and compatibility failures have distinct
exception types. Parser errors indicate that a supported backend did not
produce the expected grammar; detailed-spectrum errors retain the relevant
raw output block in the diagnostic.

```@docs
OrbifolderProcessError
OrbifolderTimeoutError
```
