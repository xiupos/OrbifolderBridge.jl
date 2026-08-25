```@meta
CurrentModule = OrbifolderBridge
```

# Overview

OrbifolderBridge connects a typed Julia model to the upstream `orbifolder` or
`nonSUSYorbifolder` executable and turns its results back into Julia values.
The usual workflow has four steps:

1. configure a backend and its `Geometry/` directory;
2. construct an [`OrbifolderModel`](@ref);
3. let upstream check or analyze it;
4. inspect the parsed spectrum, optionally as OSCAR objects.

The bridge does not reproduce upstream's physics algorithms. Spectrum
construction, modular-invariance checks, projections, and coupling selection
remain upstream computations.

Exact gauge-lattice embeddings are available through
[`compute_exact_gauge_data`](@ref). The result retains the 16-dimensional
simple roots and U(1) generators reported by upstream and can be converted to
OSCAR matrices over `QQ`; see [Exact gauge-lattice embeddings](@ref).

## A first model

The following is the ``\mathbb Z_3`` model used throughout this guide:

```julia
using OrbifolderBridge

model = OrbifolderModel(;
    mode = :nonsusy,
    label = "Z3_1_1",
    point_group = "Z3_1_1",
    shift = (
        [0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0],
        [1//3, 1//3, -2//3, zeros(Int, 13)...],
    ),
)
```

`point_group` selects `Geometry/Geometry_Z3_1_1.txt`. The shift vectors and
six optional Wilson lines specify the gauge embedding. In this non-SUSY
example, the first vector is the Witten ``\mathbb Z_2`` embedding and the
second is the compactification ``\mathbb Z_3`` embedding. See
[Models and Geometry](@ref) for the input conventions and for inspecting the
twist, shifts, and Wilson lines reported by upstream.

Compatible Geometry alternatives and the selected space-group metadata also
come directly from upstream:

```julia
available_space_groups(model)
space_group_metadata(model)
```

Before a more expensive calculation, ask upstream to validate the model:

```julia
result = check_consistency(model)
result.valid || error(result.message)
```

Infrastructure failures remain exceptions; only a confirmed upstream model
rejection produces `valid == false`. [Consistency and Batch Workflows](@ref)
also covers filtering and analyzing many models concurrently.

## From a model to fields

The grouped spectrum is the convenient overview:

```julia
spectrum = compute_spectrum(model)
spectrum.gauge_group
spectrum.fields
```

For the example it reports
``SO(10) \times SU(3) \times SO(16) \times U(1)``. Each
[`SpectrumField`](@ref) stores one group of fields with equal representation,
statistic, and abelian charges, together with its multiplicity.

Use the detailed spectrum when later results must refer to individual fields:

```julia
detailed = compute_detailed_spectrum(model)
s1 = only(find_fields(detailed; label = "s_1"))

s1.id
s1.sector
s1.localization
```

[`FieldID`](@ref) is the cross-reference identity; `"s_1"` is display-label
metadata belonging to the current label scheme. [Spectra and Fields](@ref)
explains grouped and individual views, localization, charges, and compound
queries.

## From printed dimensions to OSCAR weights

The spectrum parser deliberately returns plain values. Convert them only when
OSCAR objects are needed:

```julia
root_systems = gauge_group_root_systems(spectrum.gauge_group)
weights = field_weights(root_systems, spectrum.fields[1])
```

[OSCAR Integration](@ref) explains this conversion and the ambiguity inherent
in reconstructing a highest weight from a printed representation dimension.

## Guide map

- [Models and Geometry](@ref): model inputs and geometric/gauge embedding data.
- [Couplings and the Superpotential](@ref) and [Mass Matrices](@ref): stable
  field-linked interactions and exact OSCAR polynomial data.
- [Spectra and Fields](@ref): gauge groups, grouped spectra, individual fields,
  localization, and queries.
- [Model Classification and Generation](@ref): upstream model predicates,
  anomaly diagnostics, random candidates, and inequivalence.
- [OSCAR Integration](@ref): root systems, weights, and dual representations.
- [Consistency and Batch Workflows](@ref): validation and concurrent scans.
- [Integrated and Reproducible Analysis](@ref): related results from one
  upstream run with shared hashes, commands, warnings, and transcript.
- [VEV Configurations](@ref): explicit selection, replayable derived
  configurations, fixed SUSY VEVs, and observable/hidden sectors.
- [Backend Configuration](@ref): binary discovery, low-level execution,
  parsers, and diagnostics.
- [Design and Scope](@ref): architectural boundaries and future API direction.
- [Upstream Notes](@ref): verified command protocol and output grammar.
