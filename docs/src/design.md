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

The public interface should be declarative and typed:

```julia
model = OrbifolderModel(...)
result = analyze(model; config = "TestConfig1", include = [:spectrum, :couplings])
```

Users should not normally need to navigate the upstream prompt, manage its
current directory, parse formatted tables, or handle backend-specific output
files. `run_orbifolder_script` remains available as an escape hatch for
experimentation and features that do not yet have a typed API.

The following are outside the core bridge:

- reproducing the interactive REPL;
- upstream session and job-control user interfaces;
- presentation-oriented Mathematica, LaTeX, and text-file output modes;
- phenomenological ranking and landscape-search policy;
- independent Julia implementations of upstream physics algorithms.

## Domain model

### Stable field identity

Fields are the central entities connecting spectra, localization, VEVs,
couplings, and mass matrices. Future APIs should therefore use a stable field
identifier rather than relying on a summary row or a display label alone.

A detailed spectrum should preserve both grouped and individual views:

- the grouped view efficiently represents repeated quantum numbers;
- the individual view assigns an identity to every field;
- labels are configuration-dependent metadata, not the primary identity;
- sector and localization data belong to the individual state.

This design prevents multiplicity expansion, relabeling, or a configuration
change from breaking references held by coupling and mass-matrix results.

### VEV configuration

Any result that depends on a VEV configuration must make that configuration
explicit. It must not silently depend on the upstream prompt's current state.
The configuration connects:

- field labels and VEV assignments;
- observable and hidden gauge factors;
- the unbroken gauge group;
- the effective spectrum, superpotential, and mass matrices.

Read-only selection and inspection should precede configuration mutation.
Mutation, when added, should use immutable or copy-on-write Julia descriptions
that can be serialized and reproduced.

### Gauge and representation data

Gauge data should retain exact information whenever upstream makes it
available: simple roots, U(1) generators and normalization, anomalous
generators, and Dynkin labels or highest weights. Mapping a printed dimension
back to a representation is necessarily ambiguous and should remain a fallback,
not the preferred interchange format.

### Couplings and mass matrices

The bridge should ask upstream to compute allowed couplings and then parse the
answer. A coupling should refer to stable field identities and record relevant
order and effective-VEV information. A mass-matrix entry should remain linked
to the coupling expressions that generated it before optional conversion to an
OSCAR polynomial matrix.

## Execution model

Every invocation runs in an isolated temporary directory. Backend-specific
details—stdin-driven SUSY execution versus the non-SUSY script result file—are
internal implementation concerns.

Public operations should:

1. validate the binary, Geometry directory, version, and capabilities;
2. render deterministic input and command files;
3. execute with a timeout and collect all generated output;
4. split the transcript by command;
5. parse plain Julia values;
6. construct OSCAR objects only after parsing succeeds.

Keeping parsing separate from OSCAR construction makes parser tests cheap and
avoids unsafe parallel use of GAP-backed objects. Batch execution may launch
independent subprocesses concurrently, while OSCAR conversion remains
sequential unless the underlying libraries become safe for parallel use.

## Compatibility and capabilities

Backend kind and version are part of the computation environment. Capability
checks are preferable to scattered version conditionals:

```julia
info = backend_info(:nonsusy)
supports(info, :effective_couplings)
```

An unknown output format must cause a diagnostic failure rather than silent
partial parsing. Fixtures should identify the backend and version that produced
them. SUSY and non-SUSY fixtures should be separate whenever their command
protocol or output grammar differs.

## Reproducibility and provenance

Computed values should be traceable to:

- backend kind and version;
- the exact rendered model input or its cryptographic hash;
- Geometry data identity;
- VEV configuration;
- executed commands;
- warnings and raw transcript.

This metadata is best carried by a common result wrapper or analysis result,
rather than duplicated in every small value type. Plain parsed values should
remain convenient to compare and test.

## API evolution

Prefer small composable queries such as `compute_spectrum` for common work and
an integrated `analyze` operation when several related results must share a
single configuration and transcript. Existing low-level functions should
remain available where practical, but new public APIs should not expose prompt
paths or backend-specific file handling.

The planned implementation order and completion status are maintained in the
repository-level `ROADMAP.md`.
