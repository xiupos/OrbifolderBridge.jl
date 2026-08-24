```@meta
CurrentModule = OrbifolderBridge
```

# Models and Geometry

An [`OrbifolderModel`](@ref) describes the data needed by upstream to construct
a heterotic orbifold model: a space group, a ten-dimensional gauge lattice,
one or two shift vectors, and up to six Wilson lines. It is an input value, not
a cached upstream session.

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
group uses `(V1, V2)`. The non-SUSY backend reserves its two slots for the
Witten ``\mathbb Z_2`` embedding and the compactification point-group
embedding, respectively, as shown above.

The rendered upstream input is deterministic and can be inspected without
launching a process:

```julia
print(model_file_text(model))
```

This is useful when comparing a Julia model with an upstream `begin model ...
end model` block.

## Point-group twists

The point group acts on the compact dimensions through one or two twist
vectors. Obtain the representation actually reported by upstream with:

```julia
twist = compute_twist(model)
twist.vectors
```

[`Twist`](@ref) contains one four-dimensional rational vector for a cyclic
point group and two for a product point group.

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

## Model and geometry API

```@docs
OrbifolderModel
model_file_text
compute_twist
compute_shift_vectors
compute_wilson_lines
Twist
ShiftVector
WilsonLine
WilsonLines
```
