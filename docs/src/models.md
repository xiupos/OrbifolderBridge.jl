```@meta
CurrentModule = OrbifolderBridge
```

# Models and Geometry

An [`OrbifolderModel`](@ref) describes the data needed by upstream to construct
a heterotic orbifold model: a space group, a ten-dimensional gauge lattice,
up to three shift vectors, and six Wilson-line slots. It is an input value,
not a cached upstream session.

## Constructing a model

```julia
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

`mode` selects `:susy` (`orbifolder`) or `:nonsusy`
(`nonSUSYorbifolder`). `point_group = "Z3_1_1"` resolves to the
corresponding file below the configured `Geometry/` directory. All shifts and
Wilson lines have 16 rational entries. Missing Wilson lines are filled with
zero vectors.

For a SUSY cyclic point group, `shift` can be one vector; a SUSY product point
group uses `(V1, V2)`. The non-SUSY backend uses three slots: the Witten
``\mathbb Z_2`` embedding followed by two compactification point-group slots.
The third slot is zero for the cyclic example above and is filled
automatically when omitted.

The rendered upstream input is deterministic and can be inspected without
launching a process:

```julia
print(model_file_text(model))
```

This is useful when comparing a Julia model with an upstream `begin model ...
end model` block.

```@docs
OrbifolderModel
model_file_text
```

## Point-group twists

The point group acts on the compact dimensions through one or two twist
vectors. Obtain the representation actually reported by upstream with:

```julia
twist = compute_twist(model)
twist.vectors
```

[`Twist`](@ref) contains one four-dimensional rational vector for a cyclic
point group and two for a product point group.

```@docs
compute_twist
Twist
```

## Gauge embedding

The twist is embedded into the gauge degrees of freedom by shift vectors and
Wilson lines:

```julia
shifts = compute_shift_vectors(model)
wilson = compute_wilson_lines(model)
```

Each [`ShiftVector`](@ref) and [`WilsonLine`](@ref) retains its upstream label
and exact 16-dimensional rational vector. [`WilsonLines`](@ref) additionally
records identifications such as `W_1 = W_2` and the orders allowed by the
space group.

These operations query upstream. They do not independently derive Geometry
metadata in Julia, and an invalid embedding may be rejected before a result is
printed. Use [Consistency and Batch Workflows](@ref) to distinguish a model
rejection from an execution failure.

```@docs
compute_shift_vectors
compute_wilson_lines
ShiftVector
WilsonLine
WilsonLines
```

## Space-group catalogue and metadata

The compatible Geometry files for a model's point group can be enumerated
without interpreting their filenames:

```julia
groups = available_space_groups(model)
groups[1].lattice_label
groups[1].geometry_file
```

Each [`SpaceGroupInfo`](@ref) retains the backend because the SUSY and
non-SUSY Geometry files have different constructing-element grammars even
when their filenames coincide. The selected Geometry can be inspected with:

```julia
geometry = space_group_metadata(model)
geometry.point_group_orders
geometry.lattice_label
geometry.generators
```

[`SpaceGroupMetadata`](@ref) contains the point-group orders, compactification
root-lattice label, optional additional label, Geometry filename, and the
generators printed by upstream. A [`SpaceGroupElement`](@ref) combines a
backend-shaped [`Sector`](@ref) with the exact six-dimensional translation.
The bridge does not reproduce the upstream Geometry-file engine.

```@docs
available_space_groups
space_group_metadata
parse_available_space_groups
parse_space_group_metadata
SpaceGroupInfo
SpaceGroupMetadata
SpaceGroupElement
GeometryParseError
```
