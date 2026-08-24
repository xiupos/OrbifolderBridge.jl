# OrbifolderBridge Roadmap

## Goal

OrbifolderBridge should provide a typed, reproducible Julia/OSCAR interface to
`orbifolder` and `nonSUSYorbifolder`. It should expose the scientific inputs
and results of upstream computations without reproducing the upstream REPL,
session UI, output formatting, or physics algorithms.

The phases below express intended outcomes, not a compatibility promise or a
fixed release schedule. Design details live in
[`docs/src/design.md`](docs/src/design.md), and upstream investigation notes
live in [`docs/src/upstream_notes.md`](docs/src/upstream_notes.md).

## Phase 1: Field identity and detailed spectra

- [ ] Parse upstream field labels such as `F_1`.
- [ ] Represent individual fields without losing summary multiplicities.
- [ ] Define stable field identifiers shared by all later APIs.
- [ ] Parse twisted sectors and untwisted-sector information.
- [ ] Parse fixed-point or fixed-brane localization.
- [ ] Parse constructing elements and local shifts where upstream exposes them.
- [ ] Parse discrete charges, R charges, and multiplet types.
- [ ] Provide structured field queries by representation, charge, sector,
      statistic, and label.

## Phase 2: Backend discovery and compatibility

- [ ] Detect the backend kind and version.
- [ ] Validate the configured binary and Geometry directory together.
- [ ] Report backend capabilities through a typed API.
- [ ] Associate parsers with the output versions they support.
- [ ] Fail clearly on unsupported output instead of returning partial data.
- [ ] Add a lightweight backend self-test.

## Phase 3: VEV configurations

- [ ] List available VEV configurations.
- [ ] Select a configuration explicitly in configuration-dependent APIs.
- [ ] Read field labels and VEV assignments from a configuration.
- [ ] Read observable and hidden gauge-sector selections.
- [ ] Obtain the unbroken gauge group and spectrum after VEV assignment.
- [ ] Add non-interactive creation or modification only where it can be made
      declarative and reproducible.

## Phase 4: Exact gauge and representation data

- [ ] Parse non-abelian simple roots.
- [ ] Parse U(1) generators and their normalization.
- [ ] Parse the anomalous U(1) generator and anomaly data.
- [ ] Represent observable and hidden gauge factors explicitly.
- [ ] Obtain exact Dynkin labels or highest weights when upstream provides
      them.
- [ ] Reduce reliance on dimension-based representation inference.

## Phase 5: Couplings and superpotential

- [ ] Establish and fixture-test the non-interactive coupling protocol.
- [ ] Generate allowed couplings through upstream.
- [ ] Parse superpotential terms into structured field references.
- [ ] Support coupling searches and maximum-order restrictions.
- [ ] Parse effective couplings after VEV substitution.
- [ ] Represent or exclude couplings that vanish by symmetry as reported by
      upstream.

The bridge will not reimplement upstream selection rules in Julia.

## Phase 6: Mass matrices

- [ ] Request mass matrices for selected field families.
- [ ] Parse matrix entries and connect them to fields and couplings.
- [ ] Support effective matrices after VEV substitution.
- [ ] Convert symbolic results to suitable OSCAR polynomial rings and matrices.

## Phase 7: Geometry and localization

- [ ] Enumerate available compatible space groups.
- [ ] Expose point-group and lattice metadata.
- [ ] Represent sectors, fixed points, fixed tori, and constructing elements.
- [ ] Connect localized states to their local gauge data.

The goal is structured access to upstream results, not a second implementation
of the Geometry-file engine.

## Phase 8: Integrated and reproducible analysis

- [ ] Introduce a computation context containing model, backend,
      configuration, and execution options.
- [ ] Add an `analyze` API that obtains related results in one upstream run.
- [ ] Record backend version, model-input hash, Geometry identity, commands,
      warnings, and raw transcript as provenance.
- [ ] Extend batch APIs to integrated analyses.
- [ ] Avoid repeated subprocess launches when several results can be parsed
      from one transcript.

## Ongoing work

- [ ] Maintain SUSY and non-SUSY regression fixtures.
- [ ] Improve parser diagnostics and distinguish empty results from failures.
- [ ] Keep the raw-command escape hatch usable for experimental upstream
      features.
- [ ] Document backend support and known format differences.

## Explicit non-goals

- Reproducing the upstream interactive REPL and directory navigation.
- Exposing upstream job-control commands as the Julia concurrency model.
- Reproducing upstream text-file, Mathematica, or LaTeX presentation modes.
- Reimplementing spectrum, GSO, modular-invariance, coupling-selection, or
  F-/D-flatness algorithms in Julia.
- Building phenomenological ranking or landscape-search policy into the core
  bridge.
- Guaranteeing automatic installation of all upstream C++ build dependencies.
