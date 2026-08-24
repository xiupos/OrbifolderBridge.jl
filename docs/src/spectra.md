```@meta
CurrentModule = OrbifolderBridge
```

# Spectra and Fields

Spectrum data has two complementary views. [`Spectrum`](@ref) preserves the
compact tables printed by upstream; [`DetailedSpectrum`](@ref) assigns an
identity and localization to every individual field. Both are obtained from
the same authoritative upstream computation.

The examples on this page use `model` from [A first model](@ref).

## Gauge group

```julia
group = compute_gauge_group(model)
group.nonabelian
group.n_u1
```

[`GaugeGroup`](@ref) stores non-abelian factors in the order used by every
field representation, plus the number of ``U(1)`` factors and the active VEV
configuration label.

## Grouped spectrum

```julia
spectrum = compute_spectrum(model)

for field in spectrum.fields
    println(field.multiplicity, " × ", field.rep, "_", field.statistic,
            "  charges: ", field.charges)
end
```

A [`SpectrumField`](@ref) is one upstream summary row. `rep[i]` is the signed
printed dimension under `spectrum.gauge_group.nonabelian[i]`; a negative value
denotes the conjugate representation. `charges` contains exact rational
``U(1)`` charges. `statistic` is the upstream multiplet marker, such as `:s`,
`:f`, or `:l`.

The grouped view intentionally does not expand multiplicities. It is efficient
for representation counts and gauge-level summaries.

## Individual fields

```julia
detailed = compute_detailed_spectrum(model)

length(detailed.fields) ==
    sum(row.multiplicity for row in detailed.summary.fields)
```

Every [`DetailedField`](@ref) contains:

- a [`FieldID`](@ref) derived from upstream's `field no.`;
- the configuration-dependent field label;
- representation, statistic, and ``U(1)`` charges;
- multiplet type and sector;
- the constructing element's six translation coefficients;
- fixed-point or fixed-brane localization and the 16D local shift;
- space-group charges, R charges, and right-moving momentum when printed.

The parser verifies that individual fields reconstruct every summary
multiplicity. It also rejects duplicate identities, conflicting localization,
or an incomplete join instead of returning a partial spectrum.

## Finding fields

[`find_fields`](@ref) combines all supplied conditions:

```julia
fields = find_fields(detailed;
    representation = [16, 1, 1],
    charge = 1 => 12,
    sector = (0, 2, 0),
    statistic = :f,
)

length(fields) # 27 for the guide model
```

Use `charges = [...]` to match the complete abelian charge vector, `label` for
an exact active label, or `multiplet_type` for the normalized multiplet name.
An omitted keyword imposes no condition.

`FieldID` is preferable to a display label when connecting a field to future
VEV, coupling, or mass-matrix results. Its scope is one model and backend field
basis; the computation context planned for later phases will carry that scope
as provenance.

## Spectrum API

```@docs
compute_gauge_group
compute_spectrum
compute_detailed_spectrum
find_fields
GaugeGroup
SpectrumField
Spectrum
FieldID
Sector
FieldLocalization
DetailedField
DetailedSpectrum
```
