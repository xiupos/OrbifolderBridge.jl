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

- [x] **`[upstream]`** Expose random model generation from an existing model,
      with declarative selection of inherited and randomized shifts and Wilson
      lines.
- [x] **`[upstream]`** Expose the SM-, Pati–Salam-, and SU(5)-type
      classifications provided by upstream.
- [x] **`[upstream]`** Support the upstream net-generation filter, including
      its vector-like-exotics condition.
- [x] **`[upstream]`** Expose upstream's spectrum-based selection of
      inequivalent candidate models.
- [x] **`[upstream]`** Support refinement of candidate comparison by the number
      of couplings through a specified order.
- [x] **`[upstream]`** Expose anomaly checking and its diagnostics during model
      generation and analysis.
- [x] **`[bridge]`** Return generated models, rejection reasons, classification
      results, and provenance as typed Julia values.
- [x] **`[investigate]`** Establish which generation, classification,
      inequivalence, and anomaly options have equivalent semantics in the SUSY
      and non-SUSY backends.

The bridge exposes upstream's generator and predicates; phenomenological
scoring, ranking, and landscape-search policy remain outside its scope.

## Phase 4: VEV configurations

- [x] **`[upstream]`** List available VEV configurations.
- [x] **`[bridge]`** Select a configuration explicitly in configuration-dependent APIs.
- [x] **`[upstream]`** Read field labels and VEV assignments from a configuration
      where SUSY orbifolder exposes numerical VEVs.
- [x] **`[upstream]`** Read observable and hidden gauge-sector selections.
- [x] **`[upstream]`** Obtain the unbroken gauge group and spectrum after VEV assignment
      with the SUSY backend.
- [x] **`[upstream]`** Expose the SM-, Pati–Salam-, and SU(5)-type analysis of
      an existing VEV configuration.
- [x] **`[bridge]`** Add non-interactive creation or modification only where it can be made
      declarative and reproducible.

## Phase 5: Exact gauge and representation data

- [x] **`[upstream]`** Parse non-abelian simple roots.
- [x] **`[upstream]`** Parse U(1) generators.
- [x] **`[investigate]`** Establish the upstream convention for U(1)
      normalization. General charges use the 16-dimensional lattice inner
      product; optional classification-specific target lengths are internal
      and are not printed by the supported prompts.
- [x] **`[upstream]`** Identify the anomalous U(1) generator and retain anomaly data.
- [x] **`[bridge]`** Represent observable and hidden gauge factors explicitly.
- [x] **`[bridge]`** Construct OSCAR root and weight lattices from exact upstream
      data, retaining their embedding in the 16-dimensional gauge lattice.
- [x] **`[bridge]`** Represent U(1) generators and their Gram matrix as exact
      OSCAR rational matrices.
- [x] **`[bridge]`** Represent the intrinsic U(1) basis normalization, dual
      charge metric, and squared generator lengths as exact OSCAR rational
      matrices and values.
- [x] **`[investigate]`** Establish whether exact Dynkin labels or highest
      weights are exposed by the supported command protocols. They are used
      internally upstream but are not printed by a non-interactive command.
- [x] **`[bridge]`** Convert supplied exact Dynkin labels or highest weights to
      OSCAR `WeightLatticeElem` values associated with the corresponding gauge
      factor, ready for a future upstream output source.
- [x] **`[bridge]`** Make dimension-based representation inference an explicit,
      provenance-tagged fallback behind exact-label resolution.
- [x] **`[bridge]`** Validate reported representation dimensions against exact
      highest weights, while keeping dimension-based lookup an explicit fallback.
- [x] **`[bridge]`** Compare the exact gauge embeddings before and after a VEV
      configuration, including surviving roots and U(1) directions, without
      recomputing the upstream Higgsing decision.

## Phase 6: Couplings and superpotential

- [x] **`[investigate]`** Establish and fixture-test the non-interactive coupling protocol.
      SUSY 1.2.1 requires `create coupling(...)`, `wait(1)`, then
      `save couplings(...)`; non-SUSY 1.0 has no coupling implementation.
- [x] **`[upstream]`** Generate explicitly requested allowed couplings through
      SUSY upstream.
- [x] **`[bridge]`** Parse saved superpotential terms into structured stable
      field references after exact model-header validation.
- [x] **`[upstream]`** Support searches over explicitly registered coupling
      candidates and maximum-order restrictions. The bridge submits only
      candidates through the requested order because SUSY 1.2.1's documented
      save-file order option parses the wrong command parameter.
- [x] **`[upstream]`** Parse effective couplings after VEV substitution,
      retaining both dynamical and VEV field identities and the ordinary
      source term.
- [x] **`[upstream]`** Represent or exclude couplings that vanish by symmetry as reported by
      upstream. The available command may require an interactive `y/n`
      classification and is intentionally excluded from the batch API rather
      than replacing that physical decision in Julia.
- [x] **`[bridge]`** Construct an OSCAR polynomial ring whose generators map
      bijectively to stable field identifiers, and convert parsed couplings to
      elements of that ring.
- [x] **`[bridge]`** Express VEV substitution as an exact ring homomorphism while
      retaining the source coupling and field provenance.

The bridge will not reimplement upstream selection rules or flatness algorithms
in Julia. It exposes the upstream superpotential as OSCAR data so users can
perform their own subsequent ideal-theoretic analysis.

## Phase 7: Mass matrices

- [x] **`[upstream]`** Request mass matrices for selected field families.
- [x] **`[bridge]`** Parse matrix entries and connect them to fields and couplings.
- [x] **`[upstream]`** Support effective matrices after VEV substitution.
- [x] **`[bridge]`** Convert symbolic results to suitable OSCAR polynomial rings and matrices.
- [x] **`[bridge]`** Attach stable field identifiers to matrix rows and columns
      and retain the coupling provenance of every entry.
- [x] **`[bridge]`** Support exact specialization of polynomial mass matrices at
      a selected VEV configuration, leaving rank, minor, and determinantal-ideal
      analysis available through OSCAR.

SUSY 1.2.1 constructs matrices from registered effective couplings and may
automatically transpose wide matrices. The bridge uses temporary label
families in an isolated derived configuration, records the printed
orientation, and links each VEV monomial to its validated ordinary coupling.
non-SUSY 1.0 has no coupling or mass-matrix implementation.

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
