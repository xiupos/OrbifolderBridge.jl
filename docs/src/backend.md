```@meta
CurrentModule = OrbifolderBridge
```

# Backend Configuration

Every public computation ultimately launches one of the two upstream
executables in an isolated temporary directory. Most users only need to
configure the executable and its matching `Geometry/` directory; the remaining
functions on this page are escape hatches and parser building blocks.

## Locating binaries and Geometry data

```julia
set_orbifolder_binary!(:susy, "/path/to/orbifolder")
set_orbifolder_geometry_dir!(:susy, "/path/to/Geometry")
```

Configuration can also come from `ORBIFOLDER_BIN`,
`NONSUSYORBIFOLDER_BIN`, `ORBIFOLDER_GEOMETRY_DIR`, and
`NONSUSYORBIFOLDER_GEOMETRY_DIR`. The getter functions first resolve
environment variables, then Preferences.jl settings, then documented path
fallbacks.

The binary and Geometry directory must belong to a compatible upstream tree.
[`backend_info`](@ref) validates both paths, runs the backend through its real
isolated batch protocol, and reads the kind and version from the startup
banner:

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

```@docs
orbifolder_binary
set_orbifolder_binary!
orbifolder_geometry_dir
set_orbifolder_geometry_dir!
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
supports(info, :effective_couplings)     # false in the current bridge
```

The capability set also records backend-specific differences. In particular,
`:coupling_refined_inequivalence` is available for SUSY 1.2.1 but not
non-SUSY 1.0.

For setup diagnostics, [`check_backend`](@ref) catches configuration,
execution, timeout, and compatibility failures and returns a
[`BackendSelfTest`](@ref). A false result carries a human-readable `message`
and any output captured before the failure:

```julia
result = check_backend(:susy)
result.ok || @warn result.message
```

This check is deliberately lightweight: it verifies the executable, requires
a nonempty Geometry-file inventory, and completes the backend's normal script
protocol without loading a physical model.

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
