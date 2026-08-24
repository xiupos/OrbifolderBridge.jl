# Repository instructions

## Project role

OrbifolderBridge is a typed Julia/OSCAR bridge to the upstream `orbifolder`
and `nonSUSYorbifolder` programs. Keep upstream responsible for the physical
computations. Do not reimplement spectrum, GSO projection, coupling-selection,
or flatness algorithms in Julia.

The implementation roadmap is in `ROADMAP.md`. Architectural decisions and
the boundary of the bridge are documented in `docs/src/design.md`. Findings
about upstream programs and their command language belong in
`docs/src/upstream_notes.md`.

## API design

- Prefer typed Julia values over exposing upstream output strings.
- Do not reproduce the upstream interactive REPL or its directory-based UI.
- Keep `run_orbifolder_script` as a documented low-level escape hatch.
- Hide backend invocation differences behind a common public API when SUSY and
  non-SUSY operations have the same semantics.
- Make the VEV configuration explicit for every configuration-dependent result.
- Use stable field identifiers across spectra, VEVs, couplings, and mass
  matrices.
- Prefer exact Dynkin labels or weights reported by upstream over inferring a
  representation from its printed dimension.
- Separate transcript parsing from construction of OSCAR/GAP objects.
- Preserve backwards compatibility where practical; document intentional
  public API breaks prominently.

## Parsing and fixtures

- Base every new parser on captured output from supported upstream binaries.
- Add SUSY and non-SUSY fixtures whenever their output differs.
- Cover empty results, warnings, malformed output, and output-format drift.
- Preserve raw transcripts in diagnostic errors.
- Never silently parse an unsupported or unrecognized backend version.
- Keep fixture data minimal while retaining the complete grammar needed by the
  parser under test.

## Process execution

- Run every subprocess call in an isolated temporary directory.
- Apply timeouts to upstream invocations and clean up generated side files.
- Do not expose upstream process IDs or interactive job control as public API.
- Avoid shared mutable state so batch operations remain safe.

## Testing and documentation

- Add focused tests for every behavior change and regression fix.
- Run the relevant test files during development and the full Julia test suite
  before completing a public API change.
- Update the API reference, tutorial, design document, and roadmap when their
  documented behavior or status changes.
- Keep public docstrings usable by Documenter and include small examples for
  newly exported APIs.
