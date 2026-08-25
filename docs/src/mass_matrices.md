```@meta
CurrentModule = OrbifolderBridge
```

# Mass Matrices

OrbifolderBridge asks SUSY orbifolder to build effective mass matrices from
ordinary couplings that upstream has accepted. The bridge does not decide
which couplings are allowed or independently derive a Higgsing pattern.
The supported non-SUSY backend has no coupling or mass-matrix implementation.

## Stable row and column fields

Rows and columns are selected by stable [`FieldID`](@ref), not by the active
upstream label family. A request also lists the candidate ordinary couplings
to register and an order high enough to print their VEV products explicitly:

```julia
source = CouplingRequest([FieldID(11), FieldID(37), FieldID(39)])
request = MassMatrixRequest(
    [FieldID(11)],
    [FieldID(37)],
    [source];
    max_order = 3,
)

specification = VEVConfigurationSpec(
    name = "BridgeMatrix1",
    assignments = [VEVAssignment(FieldID(39), 1)],
    recompute_unbroken_group = false,
)

result = compute_mass_matrix(model, specification, request)
result.entries[1, 1]
```

`rows` and `columns` must be either completely disjoint or exactly equal.
When they are disjoint, the bridge assigns distinct temporary label families
(`R`, `C`) and requests upstream's `A_i M_ij B_j`-style matrix. When `rows ==
columns` — the same-family case used for a Majorana-type mass matrix, such as
right-handed-neutrino masses — both dimensions share the single `R` family
and upstream instead prints `R_i M_ij R_j`. Any other overlap is rejected
before a request reaches upstream, since neither printed form describes it.

The bridge creates the derived configuration, assigns those temporary row and
column label families, registers each coupling with its own `wait(1)` barrier,
and requests the matrix in one isolated upstream process. Temporary labels do
not escape into the result. If upstream automatically transposes a wide
matrix, `result.rows`, `result.columns`, and `result.transposed` describe the
orientation actually printed.

Each `entries[i, j]` value is a vector of [`MassMatrixTerm`](@ref)s. A term
contains the VEV fields printed in angle brackets and the complete ordinary
[`CouplingTerm`](@ref) from the validated native coupling file. Thus several
source couplings contributing to one entry retain separate provenance. A
zero entry is represented by an empty vector.

## Exact OSCAR matrices

Phase 6's exact symbolic VEV substitution supplies the coefficient ring:

```julia
ring = coupling_polynomial_ring(result.source_terms)
substitution = exact_vev_substitution(ring, [FieldID(39)])
matrix = mass_matrix_polynomial(substitution, result)
```

The matrix entries lie in the target polynomial ring over `QQ`; for example,
the source coupling above contributes `v_39`. Upstream reports allowed
monomials but no exact coupling constants, so every contribution has unit
coefficient.

Exact rational specialization is explicit:

```julia
specialized = specialize_mass_matrix(
    substitution,
    result,
    Dict(FieldID(39) => 3//2),
)
```

This returns an OSCAR matrix over `QQ`. The bridge never promotes upstream's
floating-point VEV storage to an invented exact number. Rank, minors, and
determinantal ideals remain ordinary OSCAR operations on the returned matrix.

## API

```@docs
MassMatrixRequest
MassMatrixTerm
MassMatrixResult
MassMatrixParseError
parse_mass_matrix
compute_mass_matrix
mass_matrix_polynomial
specialize_mass_matrix
```
