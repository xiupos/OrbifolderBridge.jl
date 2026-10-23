# Design and Scope

## Purpose

OrbifolderBridge connects Julia and OSCAR to the upstream `orbifolder` and
`nonSUSYorbifolder` executables. Its responsibility is to describe inputs,
execute upstream reliably, parse results into Julia values, and map suitable
mathematical data to OSCAR objects.

The bridge is deliberately not a Julia rewrite of the upstream physics engine.
Massless spectra, GSO projections, modular-invariance decisions, allowed
couplings, and vacuum-flatness calculations remain authoritative upstream.

## Boundary of the bridge

The public interface is declarative and typed:

```julia
model = OrbifolderModel(...)
result = analyze(model;
    config = VEVConfigurationRef("TestConfig1"),
    include = [:spectrum, :detailed_spectrum],
)
```

Users do not navigate the upstream prompt, manage its current directory, parse
formatted tables, or handle backend-specific output files.
`run_orbifolder_script` remains available as an escape hatch for
experimentation and features that do not yet have a typed API.

The following are outside the core bridge:

- reproducing the interactive REPL;
- upstream session and job-control user interfaces;
- presentation-oriented Mathematica, LaTeX, and text-file output modes;
- phenomenological ranking and landscape-search policy;
- independent Julia implementations of upstream physics algorithms.

## Domain model

### Stable field identity

Fields connect spectra, localization, VEVs, couplings, and mass matrices, so
results refer to them by `FieldID` rather than by a summary row or a
display label. `FieldID` wraps upstream's zero-based `field no.`, which does
not depend on the selected label scheme. Its scope is one model and backend
field basis, identified across saved analyses by
`AnalysisProvenance`.

`DetailedSpectrum` keeps both views: the grouped `Spectrum`
for repeated quantum numbers, and individually identified
`DetailedField`s carrying sector and localization data. Labels are
configuration-dependent metadata. Multiplicity expansion, relabeling, or a
configuration change therefore cannot break references held by coupling and
mass-matrix results.

### Geometry and localization

Compatible space groups are enumerated through upstream's own catalogue
command. The bridge records point-group orders, the compactification
root-lattice label, the selected Geometry file, and the generators upstream
prints. It does not reconstruct conjugacy classes, fixed sets, centralizers,
or other Geometry-engine results from the file contents.

SUSY and non-SUSY Geometry trees share filenames but not grammar: non-SUSY
adds the Witten twist coordinate. A `SpaceGroupElement` therefore contains a
backend-shaped `Sector` and a common six-entry translation, and catalogue
entries retain their backend identity.

Field localizations are grouped by the complete constructing element together
with upstream's fixed-point/fixed-brane label and exact local shift, and link
stable `FieldID`s to that location. Since upstream provides no local gauge
group, `LocalGaugeData` exposes the local shift and localized states without
deriving a group in Julia.

### VEV configuration

Every configuration-dependent result names its configuration explicitly
instead of depending on the upstream prompt's current state. The configuration
determines field labels and VEV assignments, observable and hidden gauge
factors, the unbroken gauge group, and the effective spectrum,
superpotential, and mass matrices.

`VEVConfigurationRef` selects an existing configuration. Each
operation selects it in a fresh isolated process and verifies upstream's
acknowledgement. Overloads without a reference remain for compatibility, but
reproducible code should not depend on the initially selected `TestConfig1`.
`GaugeSector` records observable and hidden factor indices separately
from algebra names.

`VEVConfigurationSpec` is an immutable replay description, since
upstream configurations exist only within one process. Materialization
resolves `FieldID`s in the base configuration, then reconstructs the derived
configuration in a second isolated run; both transcripts are retained.
Configuration derivation and observable-sector selection work on both
backends; fixed VEVs and unbroken-group recomputation are SUSY-only.

SUSY accepts VEVs by active field label and stores floating-point values. The
bridge resolves labels from `FieldID`, excludes random values, verifies
nonzero assignments through internal-information readback, and restricts
assignments to non-abelian singlets because upstream exposes no
weight-component selector.

When a non-abelian factor is hidden, upstream folds its dimension into grouped
multiplicities, so a derived result does not provide a `DetailedSpectrum` in
that case.

### Gauge and representation data

Gauge data retains exact information wherever upstream prints it. Mapping a
printed dimension back to a representation is ambiguous and remains an
explicit fallback rather than the interchange format.

`ExactGaugeData` retains upstream's simple roots and U(1) generators
as exact 16-dimensional rational vectors. The OSCAR conversion builds an
`EmbeddedGaugeFactor` per non-abelian factor whose `RootSystem`,
`WeightLattice`, embedded `ZZLat`, and fundamental-weight matrix share
upstream's simple-root numbering. Construction verifies the complete Cartan
matrix and rejects an unexpected ordering or output drift.

`compare_gauge_embeddings` compares two upstream results over `QQ`:
identical simple roots, basis-independent containment in the other root or
U(1) span, and exact intersection ranks. It describes the change upstream
reports; it does not decide which roots a VEV should break.

### Couplings and mass matrices

Upstream computes allowed couplings; the bridge parses the answer and links
every term to stable field identities.

Ordinary coupling requests are implemented for SUSY orbifolder and expressed
entirely in `FieldID`s; configuration-local labels appear only in the
rendered command. The bridge parses upstream's native `save couplings(...)`
file rather than the formatted `W = ...` display, because it stores internal
field numbers and the full gauge-embedding header. The parser checks the
header against the model and the numbers against the inspected field basis.
The non-SUSY backend has no coupling commands and does not advertise the
capability. `remove vanishing couplings` is not used, because it may ask for a
decision on raw stdin.

Coupling terms map to an OSCAR polynomial ring over `QQ` whose generators are
named after stable field numbers. Upstream reports no coupling strengths, so
monomials carry unit coefficients. Exact VEV substitution maps a VEV field to
a symbolic `v_<number>` generator rather than coercing upstream's
floating-point magnitude into an exact coefficient, and each image stays
paired with its source term.

For declarative SUSY configurations, coupling generation and `print effective
superpotential` run in the process that creates the configuration. The
effective-expression parser expands upstream's products and parenthesized
sums and matches every term back to a registered ordinary coupling; it does
not infer effective terms itself.

Mass-matrix requests identify rows and columns by `FieldID`. Because upstream
accepts label families rather than field numbers, the bridge assigns temporary
families in the derived configuration, registers explicit coupling
candidates, normalizes any automatic transpose, and matches every printed VEV
monomial to exactly one validated ordinary coupling. The OSCAR conversion uses
the same symbolic VEV ring; rational specialization is an explicit user
operation, and rank or determinantal analysis is left to OSCAR.

## Execution model

Every invocation runs in an isolated temporary directory. Backend-specific
details—stdin-driven SUSY execution versus the non-SUSY script result file—are
internal. Each public operation:

1. validates the binary, Geometry directory, version, and capabilities;
2. renders deterministic input and command files;
3. executes with a timeout and collects all generated output;
4. splits the transcript by command;
5. parses plain Julia values;
6. constructs OSCAR objects only after parsing succeeds.

Keeping parsing separate from OSCAR construction makes parser tests cheap and
avoids parallel use of GAP-backed objects: batch execution runs subprocesses
concurrently, while OSCAR conversion stays sequential.

## Compatibility and capabilities

Backend kind and version are part of the computation environment, and
capability checks replace scattered version conditionals:

```julia
info = backend_info(:susy)
supports(info, :couplings)
```

The compatibility table recognizes SUSY 1.2.1 and non-SUSY 1.0. Every public
operation performs a preflight through the backend's batch protocol, and an
unknown kind or version fails with a diagnostic rather than partial parsing.
SUSY and non-SUSY fixtures stay separate wherever their protocol or grammar
differs.

Random generation has no seed option upstream, so the bridge records the
request, accepted model blocks, backend, warnings, and sanitized transcript as
provenance without claiming that a rerun reproduces the candidates. Generated
side files are read before the temporary directory is removed and returned
only as parsed values.

## Reproducibility and provenance

`ComputationContext` fixes the model, validated backend, explicit VEV
configuration, and timeout. `analyze` returns the requested values in
an `AnalysisResult` with one shared `AnalysisProvenance`:
backend, SHA-256 of the exact rendered model input, Geometry filename and
content hash, VEV configuration, executed commands, warnings, and raw
transcript. The Geometry hash detects a changed definition under the same
filename.

The integrated command planner coalesces read-only dependencies: a detailed
spectrum supplies localization data, and exact gauge data reuses the
gauge-group and spectrum output. Coupling generation, mass matrices, random
generation, and configuration materialization keep dedicated APIs because
they start child processes, write side files, or mutate process-local state.

## API evolution

Prefer small queries such as `compute_spectrum` for common work and
`analyze` when several results must share one configuration and transcript.
Existing low-level functions remain available where practical, but new public
APIs do not expose prompt paths or backend-specific file handling.

Implementation order and status are tracked in the repository-level
`ROADMAP.md`.
