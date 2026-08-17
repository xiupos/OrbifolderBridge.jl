# OrbifolderBridge

[![Build Status](https://github.com/xiupos/OrbifolderBridge.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/xiupos/OrbifolderBridge.jl/actions/workflows/CI.yml?query=branch%3Amain)

[日本語](README.ja.md)

> **⚠ EXPERIMENTAL — NO MAINTENANCE GUARANTEE**
>
> This package is a temporary bridge and is **not registered** in the Julia General registry.
> It exists solely to expose the C++ `orbifolder`/`nonSUSYorbifolder` tools to OSCAR.jl users
> until (if ever) the functionality is integrated upstream. Expect breaking changes without
> notice. Do not depend on it in production code.

A Julia bridge to two C++ tools for constructing and analyzing heterotic string orbifold
compactifications:

- [**orbifolder**](https://orbifolder.hepforge.org/) (Nilles, Ramos-Sánchez, Vaudrevange,
  Wingerter, [arXiv:1110.5229](https://arxiv.org/abs/1110.5229)) — the supersymmetric
  heterotic orbifolder
- [**nonSUSYorbifolder**](https://github.com/StringsIFUNAM/nonSUSYorbifolder)
  (Escalante-Notario, Pérez-Martínez, Ramos-Sánchez, Vaudrevange,
  [arXiv:2504.20137](https://arxiv.org/abs/2504.20137)) — its non-SUSY fork

Both tools are driven as subprocesses (`mode = :susy` / `:nonsusy`): `OrbifolderBridge.jl`
writes a model file and a list of `CPrompt` commands, runs the appropriate binary in its own
temporary directory, and parses the text transcript back into Julia structs — optionally
further mapped onto genuine `Oscar.RootSystem`/`Oscar.WeightLatticeElem` objects for the gauge
group and matter representations.

**You must build `orbifolder`/`nonSUSYorbifolder` yourself** — this package does not bundle or
auto-build them. See [Installation](#installation) below.

## Installation

Add the package (development mode, since it is unregistered):

```julia
using Pkg
Pkg.develop(url="https://github.com/xiupos/OrbifolderBridge.jl")
```

### Building the upstream tools

Build whichever backend(s) you need from source and make sure the resulting binary is
discoverable — either on `PATH`, or via the environment variables / `Preferences.jl` settings
described below. See [`docs/upstream_notes.md`](docs/upstream_notes.md) for build dependencies
(GSL, Boost, GNU Readline, and — for `nonSUSYorbifolder` — Autotools) and troubleshooting notes.

```bash
# nonSUSYorbifolder
git clone https://github.com/StringsIFUNAM/nonSUSYorbifolder.git
cd nonSUSYorbifolder
autoreconf -fi   # the repo doesn't ship pre-generated autotools files
./configure && make
# -> ./nonSUSYorbifolder

# orbifolder (SUSY)
curl -O https://orbifolder.hepforge.org/source/V1.2.1/orbifolder-1.2.1.tgz
tar xzf orbifolder-1.2.1.tgz && cd orbifolder-1.2.1
./configure && make
# -> ./src/orbifolder/orbifolder
```

Then either put the binaries on `PATH` under their upstream names (`orbifolder`,
`nonSUSYorbifolder`), or point at them explicitly:

```julia
using OrbifolderBridge

# one-off, for this session:
ENV["ORBIFOLDER_BIN"] = "/path/to/orbifolder"
ENV["NONSUSYORBIFOLDER_BIN"] = "/path/to/nonSUSYorbifolder"

# or persisted across sessions via Preferences.jl:
set_orbifolder_binary!(:susy, "/path/to/orbifolder")
set_orbifolder_binary!(:nonsusy, "/path/to/nonSUSYorbifolder")
```

Each backend also needs its `Geometry/` directory (shipped space-group definition files, at
the root of the source tree you built). By default it's found automatically next to the
binary; override with `ORBIFOLDER_GEOMETRY_DIR`/`NONSUSYORBIFOLDER_GEOMETRY_DIR` or
`set_orbifolder_geometry_dir!` if it isn't.

## Quick start

```julia
using OrbifolderBridge

# A Z3 orbifold on the E8xE8 lattice (point group "Z3_1_1", shipped as
# Geometry/Geometry_Z3_1_1.txt in both backends' source trees).
model = OrbifolderModel(;
    mode = :nonsusy,
    label = "Z3_1_1",
    point_group = "Z3_1_1",
    shift = (
        [0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0],
        [1//3, 1//3, -2//3, zeros(Int, 13)...],
    ),
)

spectrum = compute_spectrum(model)
println(spectrum.gauge_group)                 # GaugeGroup("TestConfig1", ["SO(10)","SU(3)","SO(16)"], 1)
println(length(spectrum.fields))               # 13

for f in spectrum.fields
    println(f.multiplicity, " × ", f.rep, "_", f.statistic, "  charges: ", f.charges)
end
```

### Mapping onto OSCAR root systems and representations

```julia
using Oscar, OrbifolderBridge

root_systems = gauge_group_root_systems(spectrum.gauge_group)  # Vector{RootSystem}, one per factor

for f in spectrum.fields
    weights = field_weights(root_systems, f)   # Vector{WeightLatticeElem}
    println(f.multiplicity, " × ", weights)
end
```

### Many models in parallel

```julia
models = [OrbifolderModel(; mode = :nonsusy, label = "M$i", point_group = "Z3_1_1", shift = shift_i)
          for (i, shift_i) in enumerate(candidate_shifts)]

spectra = compute_spectra(models; ntasks = 8)  # asyncmap over subprocess launches; parsing is sequential
```

## API

### Model construction

- `OrbifolderModel(; mode, label, point_group, shift, lattice = :E8xE8, wilson_lines = [])` —
  construct a model. `shift` is a single 16-vector \\(V_1\\) or a pair \\((V_1, V_2)\\); see the
  docstring for the full field reference.
- `model_file_text(model)` — render the upstream `begin model ... end model` file text.

### Computing model data

Single-model, sequential:

- `compute_spectrum(model)` → `Spectrum`
- `compute_gauge_group(model)` → `GaugeGroup`
- `compute_twist(model)` → `Twist`
- `compute_shift_vectors(model)` → `Vector{ShiftVector}`
- `compute_wilson_lines(model)` → `WilsonLines`

Multi-model, parallel (`ntasks` keyword controls concurrency; see
[Architecture](#architecture) below):

- `compute_spectra`, `compute_gauge_groups`, `compute_twists`,
  `compute_shift_vectors_batch`, `compute_wilson_lines_batch`

### OSCAR mapping

- `algebra_to_cartan_type(algebra)` → `(family::Symbol, rank::Int)`, e.g. `"SU(3)" -> (:A, 2)`
- `gauge_group_root_systems(gauge_group)` → `Vector{RootSystem}`
- `representation_weight(root_system, rep)` / `field_weights(root_systems, field)` → dominant
  weight(s) matching the printed representation dimension(s), via `find_weight_of_dimension`
  and (for negative/conjugate dimensions) `dual_weight`

### Lower-level building blocks

- `run_orbifolder_script(mode, commands; files, timeout)` — run a raw command list against
  either backend and get back the text transcript
- `split_transcript(text)` / `output_for(pairs, command)` — split a transcript into
  `command => output` pairs
- `parse_gauge_group`, `parse_spectrum`, `parse_twist`, `parse_shift_vectors`,
  `parse_wilson_lines` — parse a specific command's output text directly

## Known limitations

- Only the default vev-configuration (`"TestConfig1"`) is supported; switching
  vev-configurations is not yet implemented.
- Allowed superpotential couplings (`cd couplings`) are not yet parsed — the command protocol
  was explored but not fully worked out; see `docs/upstream_notes.md`.
- `find_weight_of_dimension` resolves a representation's printed *dimension* to a weight via a
  bounded search over small Dynkin-label combinations. This covers every representation that
  actually appears in these models' output (fundamentals, adjoints, vectors, spinors, ...), but
  is not a fully general inverse of the Weyl dimension formula.

## Architecture

Each subprocess call runs in its own `mktempdir()`, so parallel calls (`compute_spectra` etc.)
never share files. Only the "launch binary, wait, capture text" step is parallelized via
`asyncmap`; parsing — and especially building OSCAR/GAP objects — is done sequentially
afterward, since GAP is not thread-safe.

See [`docs/upstream_notes.md`](docs/upstream_notes.md) for how the two backends' command
languages and output formats were reverse-engineered, and for the procedure to follow when
upstream ships a new version.

## Requirements

- Julia ≥ 1.10
- Oscar.jl ≥ 1
- `orbifolder` and/or `nonSUSYorbifolder`, built from source (see above)

## License

[MIT](LICENSE) for this bridge package. The upstream `orbifolder`/`nonSUSYorbifolder` tools
you build and run separately are licensed under the GPL — see their respective repositories.
