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
Automatic version/capability validation is planned but not yet part of the
public API.

```@docs
orbifolder_binary
set_orbifolder_binary!
orbifolder_geometry_dir
set_orbifolder_geometry_dir!
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

[`split_transcript`](@ref) separates the response by echoed command and
[`output_for`](@ref) selects one command's output. The `parse_*` functions turn
captured output into plain Julia values. They are useful when developing a new
typed operation; ordinary callers should prefer `compute_*`.

```@docs
run_orbifolder_script
run_capture
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

Backend timeouts and nonzero exits have distinct exception types. Parser
errors indicate that a successful process did not produce the supported
grammar; detailed-spectrum errors retain the relevant raw output block in the
diagnostic.

```@docs
OrbifolderProcessError
OrbifolderTimeoutError
```
