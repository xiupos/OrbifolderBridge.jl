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

Each item is tagged by where the underlying capability comes from:

- **`[upstream]`** — the scientific operation or information already exists in
  `orbifolder` or `nonSUSYorbifolder`; the roadmap item is to expose or parse it.
- **`[bridge]`** — Julia API, data modeling, execution, diagnostics, or OSCAR
  integration that belongs specifically to this bridge.
- **`[investigate]`** — availability, command protocol, output stability, or
  parity between the supported upstream backends still needs to be established.

A tag does not indicate completion; the checkbox remains the implementation
status of OrbifolderBridge.

## Phase 1: Field identity and detailed spectra

- [x] **`[upstream]`** Parse upstream field labels such as `F_1`.
- [x] **`[bridge]`** Represent individual fields without losing summary multiplicities.
- [x] **`[bridge]`** Define stable field identifiers shared by all later APIs.
- [x] **`[upstream]`** Parse twisted sectors and untwisted-sector information.
- [x] **`[upstream]`** Parse fixed-point or fixed-brane localization.
- [x] **`[upstream]`** Parse constructing elements and local shifts where upstream exposes them.
- [x] **`[upstream]`** Parse discrete charges, R charges, and multiplet types.
- [x] **`[bridge]`** Provide structured field queries by representation, charge, sector,
      statistic, and label.

## Phase 2: Backend discovery and compatibility

- [x] **`[bridge]`** Detect the backend kind and version.
- [x] **`[bridge]`** Validate the configured binary and Geometry directory together.
- [x] **`[bridge]`** Report backend capabilities through a typed API.
- [x] **`[bridge]`** Associate parsers with the output versions they support.
- [x] **`[bridge]`** Fail clearly on unsupported output instead of returning partial data.
- [x] **`[bridge]`** Add a lightweight backend self-test.

## Phase 3: Upstream model generation and classification

- [ ] **`[upstream]`** Expose random model generation from an existing model,
      with declarative selection of inherited and randomized shifts and Wilson
      lines.
- [ ] **`[upstream]`** Expose the SM-, Pati–Salam-, and SU(5)-type
      classifications provided by upstream.
- [ ] **`[upstream]`** Support the upstream net-generation filter, including
      its vector-like-exotics condition.
- [ ] **`[upstream]`** Expose upstream's spectrum-based selection of
      inequivalent candidate models.
- [ ] **`[upstream]`** Support refinement of candidate comparison by the number
      of couplings through a specified order.
- [ ] **`[upstream]`** Expose anomaly checking and its diagnostics during model
      generation and analysis.
- [ ] **`[bridge]`** Return generated models, rejection reasons, classification
      results, and provenance as typed Julia values.
- [ ] **`[investigate]`** Establish which generation, classification,
      inequivalence, and anomaly options have equivalent semantics in the SUSY
      and non-SUSY backends.

The bridge exposes upstream's generator and predicates; phenomenological
scoring, ranking, and landscape-search policy remain outside its scope.

## Phase 4: VEV configurations

- [ ] **`[upstream]`** List available VEV configurations.
- [ ] **`[bridge]`** Select a configuration explicitly in configuration-dependent APIs.
- [ ] **`[upstream]`** Read field labels and VEV assignments from a configuration.
- [ ] **`[upstream]`** Read observable and hidden gauge-sector selections.
- [ ] **`[upstream]`** Obtain the unbroken gauge group and spectrum after VEV assignment.
- [ ] **`[upstream]`** Expose the SM-, Pati–Salam-, and SU(5)-type analysis of
      an existing VEV configuration.
- [ ] **`[bridge]`** Add non-interactive creation or modification only where it can be made
      declarative and reproducible.

## Phase 5: Exact gauge and representation data

- [ ] **`[upstream]`** Parse non-abelian simple roots.
- [ ] **`[upstream]`** Parse U(1) generators and their normalization.
- [ ] **`[upstream]`** Parse the anomalous U(1) generator and anomaly data.
- [ ] **`[bridge]`** Represent observable and hidden gauge factors explicitly.
- [ ] **`[investigate]`** Obtain exact Dynkin labels or highest weights when upstream provides
      them.
- [ ] **`[bridge]`** Reduce reliance on dimension-based representation inference.

## Phase 6: Couplings and superpotential

- [ ] **`[investigate]`** Establish and fixture-test the non-interactive coupling protocol.
- [ ] **`[upstream]`** Generate allowed couplings through upstream.
- [ ] **`[bridge]`** Parse superpotential terms into structured field references.
- [ ] **`[upstream]`** Support coupling searches and maximum-order restrictions.
- [ ] **`[upstream]`** Parse effective couplings after VEV substitution.
- [ ] **`[upstream]`** Represent or exclude couplings that vanish by symmetry as reported by
      upstream.

The bridge will not reimplement upstream selection rules in Julia.

## Phase 7: Mass matrices

- [ ] **`[upstream]`** Request mass matrices for selected field families.
- [ ] **`[bridge]`** Parse matrix entries and connect them to fields and couplings.
- [ ] **`[upstream]`** Support effective matrices after VEV substitution.
- [ ] **`[bridge]`** Convert symbolic results to suitable OSCAR polynomial rings and matrices.

## Phase 8: Geometry and localization

- [ ] **`[upstream]`** Enumerate available compatible space groups.
- [ ] **`[upstream]`** Expose point-group and lattice metadata.
- [ ] **`[investigate]`** Represent sectors, fixed points, fixed tori, and constructing elements
      beyond the detailed-spectrum data already exposed.
- [ ] **`[bridge]`** Connect localized states to their local gauge data.

The goal is structured access to upstream results, not a second implementation
of the Geometry-file engine.

## Phase 9: Integrated and reproducible analysis

- [ ] **`[bridge]`** Introduce a computation context containing model, backend,
      configuration, and execution options.
- [ ] **`[bridge]`** Add an `analyze` API that obtains related results in one upstream run.
- [ ] **`[bridge]`** Record backend version, model-input hash, Geometry identity, commands,
      warnings, and raw transcript as provenance.
- [ ] **`[bridge]`** Extend batch APIs to integrated analyses.
- [ ] **`[bridge]`** Avoid repeated subprocess launches when several results can be parsed
      from one transcript.

## Ongoing work

- [ ] **`[bridge]`** Maintain SUSY and non-SUSY regression fixtures.
- [ ] **`[bridge]`** Improve parser diagnostics and distinguish empty results from failures.
- [ ] **`[bridge]`** Keep the raw-command escape hatch usable for experimental upstream
      features.
- [ ] **`[bridge]`** Document backend support and known format differences.

## Explicit non-goals

- Reproducing the upstream interactive REPL and directory navigation.
- Exposing upstream job-control commands as the Julia concurrency model.
- Reproducing upstream text-file, Mathematica, or LaTeX presentation modes.
- Reimplementing spectrum, GSO, modular-invariance, coupling-selection, or
  F-/D-flatness algorithms in Julia.
- Building phenomenological ranking or landscape-search policy into the core
  bridge.
- Guaranteeing automatic installation of all upstream C++ build dependencies.
