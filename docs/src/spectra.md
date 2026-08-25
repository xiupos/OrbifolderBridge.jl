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
config = VEVConfigurationRef("TestConfig1")
group = compute_gauge_group(model, config)
group.nonabelian
group.n_u1
```

[`GaugeGroup`](@ref) stores non-abelian factors in the order used by every
field representation, plus the number of ``U(1)`` factors and the active VEV
configuration label.

```@docs
compute_gauge_group
GaugeGroup
```

## Grouped spectrum

```julia
spectrum = compute_spectrum(model, config)

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

```@docs
compute_spectrum
SpectrumField
Spectrum
```

## Individual fields

```julia
detailed = compute_detailed_spectrum(model, config)

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

```@docs
compute_detailed_spectrum
FieldID
Sector
FieldLocalization
DetailedField
DetailedSpectrum
```

## Localized states and local shifts

Turn the field-level localization data into one object per fixed point or
fixed brane:

```julia
locations = localizations(detailed)
location = first(locations)
states = fields_at(location, detailed)
local = local_gauge_data(location, detailed)
```

[`Localization`](@ref) is keyed by the complete constructing element, not by
its display label alone. It retains the exact 16D local shift and stable
[`FieldID`](@ref)s at that location. [`LocalGaugeData`](@ref) joins those IDs
to the detailed states. It deliberately does not infer a local gauge group
from the shift; upstream remains responsible for that physical computation.

Use `compute_localizations(model, config)` when a detailed spectrum has not
already been obtained.

```@docs
Localization
LocalGaugeData
localizations
compute_localizations
fields_at
local_gauge_data
```

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

```@docs
find_fields
```
