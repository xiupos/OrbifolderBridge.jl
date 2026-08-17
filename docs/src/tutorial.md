```@meta
CurrentModule = OrbifolderBridge
```

# Tutorial

This tutorial walks through building a heterotic orbifold model with `OrbifolderBridge.jl`,
computing its gauge group and massless spectrum, and mapping the result onto genuine
`Oscar.RootSystem`/`Oscar.WeightLatticeElem` objects. It also explains, briefly, the physics
behind the numbers so that the output of [`compute_spectrum`](@ref) is more than a wall of
integers.

The two upstream tools this package wraps are themselves described, with their own worked
examples, in:

- H.P. Nilles, S. Ramos-Sánchez, P.K.S. Vaudrevange, A. Wingerter,
  *"The Orbifolder: A Tool to Study the Low Energy Effective Theory of Heterotic Orbifolds"*,
  [arXiv:1110.5229](https://arxiv.org/abs/1110.5229) — the SUSY `orbifolder`.
- E. Escalante-Notario, I. Pérez-Martínez, S. Ramos-Sánchez, P.K.S. Vaudrevange,
  *"NonSUSYorbifolder"*, [arXiv:2504.20137](https://arxiv.org/abs/2504.20137) — the
  non-SUSY fork.

This page assumes you've already followed [Installation](@ref) and have a working
`orbifolder` and/or `nonSUSYorbifolder` binary.

## Background: what a heterotic orbifold model *is*

A heterotic orbifold compactifies the six extra dimensions of the heterotic string on
$\mathbb{R}^6 / S$, where $S$ is a *space group* built from:

- a **point group** $P$ of discrete rotations — Abelian, either $\mathbb{Z}_M$ or
  $\mathbb{Z}_M \times \mathbb{Z}_N$ — represented by one or two **twist vectors** $v_1$
  (and $v_2$), and
- a **lattice** $\Gamma$ of translations that $P$ must map to itself.

Modular invariance of the string on the worldsheet requires this geometric action to be
accompanied by an action on the 16 left-moving gauge degrees of freedom. For the shift
embeddings this package supports, that action is encoded by two 16-dimensional **shift
vectors** $V_1$, $V_2$ (one per twist) and up to six 16-dimensional **Wilson lines**
$W_1,\ldots,W_6$ (one per lattice translation), all living in the $E_8\times E_8$ or
$\mathrm{Spin}(32)/\mathbb{Z}_2$ root lattice. These vectors aren't free: modular invariance
imposes integrality/mod-2 conditions on $V_i\cdot V_j$, $V_i \cdot W_\alpha$ and
$W_\alpha\cdot W_\beta$ — see section 2 of either paper above for the precise conditions.
The upstream binary checks them for you and refuses to load an inconsistent model, which is
also why `compute_*` can fail with an [`OrbifolderProcessError`](@ref) if you pick shifts by
hand without paying attention to these constraints.

Given a consistent set of $(P, \Gamma, V_1, V_2, W_1,\ldots,W_6)$, the massless 4D spectrum
splits into an **untwisted sector** (the surviving pieces of the 10D gauge and gravity
multiplets) and **twisted sectors**, one per non-trivial space-group element up to
conjugacy. Massless states in a given sector satisfy a level-matching condition on shifted
left/right-moving momenta $p_{\mathrm{sh}} = p + V_g$, $q_{\mathrm{sh}} = q + v_g$, where
$V_g$/$v_g$ are the *local* shift/twist of that sector; $p_{\mathrm{sh}}$ is what determines
the state's representation under the 4D gauge group. All of this machinery lives inside the
C++ binary — `OrbifolderBridge.jl` only has to hand it a model file and parse back what comes
out.

## Building a model

[`OrbifolderModel`](@ref) is the Julia-side counterpart of the upstream `begin model ... end
model` file. The example below is the $\mathbb{Z}_3$ orbifold shipped as
`Models/ZN_models/modelZ3_1_1.txt` with both backends — the same file the NonSUSYorbifolder
paper itself uses to build $SU(5)$ GUT models in its own tutorial section:

```julia
using OrbifolderBridge

model = OrbifolderModel(;
    mode = :nonsusy,
    label = "Z3_1_1",
    point_group = "Z3_1_1",         # -> Geometry/Geometry_Z3_1_1.txt
    shift = (
        [0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0],
        [1//3, 1//3, -2//3, zeros(Int, 13)...],
    ),
    # wilson_lines defaults to all zero, i.e. no Wilson lines
)
```

`point_group` names a space-group file shipped under `Geometry/` in both upstream source
trees; `shift` here is a `(V_1, V_2)` pair straight out of that model file. You can inspect
what will actually be sent to the backend with [`model_file_text`](@ref):

```julia
print(model_file_text(model))
```
```
begin model
Label:Z3_1_1
SpaceGroup:Geometry/Geometry_Z3_1_1.txt
Lattice:E8xE8
Shifts and Wilsonlines:
0/1 0/1 0/1 1/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 1/1 0/1 0/1 0/1 0/1
1/3 1/3 -2/3 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1
0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1
0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1
0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1
0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1
0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1
0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1
end model
```

## Inspecting the twist, shift, and Wilson lines

[`compute_twist`](@ref), [`compute_shift_vectors`](@ref) and [`compute_wilson_lines`](@ref)
round-trip `model` through the backend and parse back what it reports (which can differ in
*presentation* — e.g. reduced modulo the lattice — though not in value from what you passed
in):

```julia
twist = compute_twist(model)
# Twist([[0//1, 1//3, 1//3, -2//3]])  -- a single Z3 twist vector v_1

shifts = compute_shift_vectors(model)
# [ShiftVector("V_1", [1//3, 1//3, -2//3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])]

wilson_lines = compute_wilson_lines(model)
# WilsonLines with all six W_i == 0, identified in pairs (W_1=W_2, W_3=W_4, W_5=W_6)
# by the Z3 point group, allowed order 3 for each
```

Since this is a plain $\mathbb{Z}_3$ point group there's only one twist vector $v_1 =
(0,\,1/3,\,1/3,\,-2/3)$ — note the entries sum to zero, the condition that guarantees
$\mathcal{N}=1$ in 4D — and correspondingly one non-trivial shift vector reported.

## Computing the gauge group and spectrum

```julia
spectrum = compute_spectrum(model)
```

For this model, `spectrum.gauge_group` is

```julia
GaugeGroup("TestConfig1", ["SO(10)", "SU(3)", "SO(16)"], 1)
```

i.e. a 4D gauge group $SO(10) \times SU(3) \times SO(16) \times U(1)$, reported in the
backend's default vev-configuration `"TestConfig1"`. `spectrum.anomalous_tr_q` is `21000.0`
— the lone $U(1)$ is anomalous, with $\operatorname{tr} Q_{\mathrm{anom}} = 21000$
(cancelled in the full string theory by the Green-Schwarz mechanism, not something this
package computes).

`spectrum.fields` has 13 rows; here are the first few:

```julia
13-element Vector{SpectrumField}:
  SpectrumField(3,  [10,  3, 1], :s, [-24//1])
  SpectrumField(3,  [ 1,  3, 1], :s, [ 48//1])
  SpectrumField(27, [10,  1, 1], :s, [-24//1])
  SpectrumField(27, [ 1,  1, 1], :s, [ 48//1])
  SpectrumField(81, [ 1, -3, 1], :s, [  0//1])
  SpectrumField(1,  [16,  1, 1], :f, [-36//1])
  SpectrumField(1,  [ 1,  1,-128], :f, [ 0//1])
  ⋮
```

Each [`SpectrumField`](@ref) row is `multiplicity` copies of a state transforming in
representation `rep` — one signed integer per non-abelian factor of `gauge_group.nonabelian`,
in the same order, where a negative entry denotes the conjugate representation (`-3` is
$\overline{\mathbf{3}}$ of the middle $SU(3)$ factor) — with $U(1)$ `charges`, tagged `:s`
(scalar) or `:f` (fermion) by `statistic`. So the first row reads: 3 copies of a scalar in
the $(\mathbf{10}, \mathbf{3}, \mathbf{1})$ of $SO(10)\times SU(3)\times SO(16)$, with $U(1)$
charge $-24$. The `81`-multiplicity row of $(\mathbf{1}, \overline{\mathbf{3}}, \mathbf{1})$
scalars is a twisted-sector state — the large multiplicities and denominators you'll see in
bigger models come directly from counting inequivalent fixed points per twisted sector, per
the massless-state analysis summarized above.

## Mapping onto genuine OSCAR objects

The `rep` and `charges` above are just parsed text. [`gauge_group_root_systems`](@ref) and
[`field_weights`](@ref) turn them into real `Oscar.RootSystem`/`Oscar.WeightLatticeElem`
objects you can compute with:

```julia
using Oscar

root_systems = gauge_group_root_systems(spectrum.gauge_group)
# 3-element Vector{RootSystem}:
#  Root system of type D5   (from "SO(10)")
#  Root system of type A2   (from "SU(3)")
#  Root system of type D8   (from "SO(16)")

for f in spectrum.fields[1:4]
    println(f.multiplicity, " x ", f.rep, " -> ", field_weights(root_systems, f))
end
```
```
3 x [10, 3, 1] -> WeightLatticeElem[w_1, w_1, 0]
3 x [1, 3, 1] -> WeightLatticeElem[0, w_1, 0]
27 x [10, 1, 1] -> WeightLatticeElem[w_1, 0, 0]
27 x [1, 1, 1] -> WeightLatticeElem[0, 0, 0]
```

`w_1` is the first fundamental weight of the corresponding root system — e.g. for $D_5$
that's the highest weight of the vector representation $\mathbf{10}$ of $SO(10)$, matching
the printed dimension. [`representation_weight`](@ref) (used internally here) resolves a
signed dimension to a weight via a bounded search over small Dynkin-label combinations
([`find_weight_of_dimension`](@ref)) — see [Known limitations](@ref) for what this can and
can't resolve — and flips to the dual representation via [`dual_weight`](@ref) for negative
entries.

## A SUSY example

The same API works with `mode = :susy` against the `orbifolder` binary. As a larger,
more realistic example, `test/fixtures/susy/modelMSSM0.txt` is a $\mathbb{Z}_3\times
\mathbb{Z}_3$ model (extracted from the 77-model example file shipped with the SUSY
orbifolder) whose gauge group has five non-abelian factors and nine $U(1)$s:

```julia
GaugeGroup("TestConfig1", ["SU(3)", "SU(2)", "SU(3)", "SU(2)", "SU(2)"], 9)
```

with over 60 [`SpectrumField`](@ref) rows tagged `:l` (left-chiral superfields, the SUSY
orbifolder's statistic label) rather than `:s`/`:f`. Building it follows exactly the same
pattern as above — a `(V_1, V_2)` shift pair, six Wilson lines, `mode = :susy` — just with a
$\mathbb{Z}_3\times\mathbb{Z}_3$ point group's two independent twist vectors instead of one.

## Scanning many models

[`compute_spectra`](@ref) and friends run several models' subprocesses concurrently (each in
its own temporary directory, so they can't interfere with each other) and then parse the
results sequentially, since building `Oscar`/`GAP` objects isn't thread-safe:

```julia
models = [
    OrbifolderModel(; mode = :nonsusy, label = "M$i", point_group = "Z3_1_1", shift = shift_i)
    for (i, shift_i) in enumerate(candidate_shifts)
]
spectra = compute_spectra(models; ntasks = 8)
```

This is the pattern to reach for when scanning many shift-vector/Wilson-line choices for
phenomenologically interesting spectra, à la the "Mini-Landscape" studies referenced in the
orbifolder papers — except that generating and filtering the candidate models themselves
(what upstream's own `create random orbifold from(...)` command does interactively) is not
currently exposed by this package; see [Known limitations](@ref).

## Where to go from here

- [API Reference](@ref) for the full list of exported functions and types.
- [Upstream Notes](@ref) for how the two binaries are actually driven under the hood, the
  model/geometry file formats, and build troubleshooting.
- The [Known limitations](@ref) section of [index.md](index.md) for what isn't (yet) supported:
  non-default vev-configurations, superpotential couplings, and the caveats of
  [`find_weight_of_dimension`](@ref)'s bounded search.
