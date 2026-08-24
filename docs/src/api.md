```@meta
CurrentModule = OrbifolderBridge
```

# API Reference

## Model construction

```@docs
OrbifolderModel
model_file_text
```

## Computing model data

Consistency checking:

```@docs
ConsistencyResult
check_consistency
is_consistent
check_consistency_batch
partition_consistent_models
```

Single-model, sequential:

```@docs
compute_spectrum
compute_detailed_spectrum
compute_gauge_group
compute_twist
compute_shift_vectors
compute_wilson_lines
```

Multi-model, parallel:

```@docs
compute_spectra
compute_gauge_groups
compute_twists
compute_shift_vectors_batch
compute_wilson_lines_batch
```

## Parsed data types

```@docs
GaugeGroup
SpectrumField
Spectrum
FieldID
Sector
FieldLocalization
DetailedField
DetailedSpectrum
Twist
ShiftVector
WilsonLine
WilsonLines
```

## OSCAR mapping

```@docs
algebra_to_cartan_type
gauge_group_root_systems
representation_weight
field_weights
find_weight_of_dimension
dual_weight
```

## Binary and Geometry directory configuration

```@docs
orbifolder_binary
set_orbifolder_binary!
orbifolder_geometry_dir
set_orbifolder_geometry_dir!
```

## Lower-level building blocks

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
find_fields
parse_twist
parse_shift_vectors
parse_wilson_lines
```

## Errors

```@docs
OrbifolderProcessError
OrbifolderTimeoutError
```
