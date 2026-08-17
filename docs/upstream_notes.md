# Upstream notes: orbifolder / nonSUSYorbifolder

Findings from Phase 1 investigation (2026-08-17), covering how the two upstream
C++ tools are built and driven, and what output they produce. This is the basis
for the subprocess-driven design (`src/core/`).

## Sources

- **orbifolder** (SUSY): tarball from hepforge, `https://orbifolder.hepforge.org/source/V1.2.1/orbifolder-1.2.1.tgz`.
  The hepforge site itself is not bot-blocked; only the top-level page doesn't
  link the tarball directly — go via `/source/` to find versioned `.tgz`/`.zip`
  links. Ships pre-generated autotools files (`configure`, `aclocal.m4`, ...).
- **nonSUSYorbifolder**: `git clone https://github.com/StringsIFUNAM/nonSUSYorbifolder.git`.
  Autotools-generated files (`aclocal.m4`, `configure`, `Makefile.in`, `libtool`,
  `Config/config.h`, ...) are gitignored upstream and must be regenerated with
  `autoreconf -fi` before `./configure && make` — the repo does not ship them.

Neither upstream repo is vendored into this package's git history; Phase 2
should fetch them at build/deps time (e.g. into a Scratch/Preferences-configured
directory), matching the "detect or build" pattern already used for build steps
in `GrobCovBridge.jl`/`OscarHCBridge.jl`-style bridges.

## Build dependencies

Both tools need, at minimum:
- GSL (`gsl` — note: `gsl-config` must be on `PATH`)
- Boost headers ≥ 1.60 (`boost` package on Arch; `libboost-math-dev` on Ubuntu per upstream INSTALL)
- GNU Readline (`readline`/`libreadline-dev`)
- Autotools (`autoconf`, `automake`, `libtool`) — needed for nonSUSYorbifolder
  since its generated files aren't shipped; not needed for orbifolder if its
  shipped `configure` is used as-is.

Both configure cleanly and build with a modern g++ (only deprecation warnings,
e.g. `std::binary_function`, `bind2nd` — harmless on gcc ~16).

## Class architecture (shared fork lineage)

Both tools share the same `src/` layout and core classes, confirming the spec's
premise:

```
src/io/           - CPrint (output formatting), Error, input helpers
src/linalg/       - eigenSystem and linear-algebra helper classes/criteria
src/groupTheory/  - dynkin, freudenthal, cirrep, gaugeGroupFactor, gaugeGroup,
                    weightsystem, dynkinDiagram
src/orbifolder/   - COrbifold, CSpectrum, CGaugeInvariance, CSpaceGroup,
                    CAnalyseModel, CPrompt, CPrint, CWilsonLine(s), CShiftVector,
                    CTwist, CField, CFixedBrane, ...
```

nonSUSYorbifolder adds non-SUSY-specific mass/GSO logic on top (per its own
docs and arXiv:2504.20137) but the directory/class structure and CLI are
otherwise the same generation of code as orbifolder v1.2.1.

## Driving the binaries non-interactively (critical for the subprocess design)

Both tools are built around an interactive REPL (`CPrompt`, GNU Readline) with
a Unix-path-like navigation model (`cd Label`, `cd spectrum`, `cd model`, `cd
gauge group`, ...). Both are usable in batch mode, but **the two entrypoints
differ**:

### nonSUSYorbifolder — has a documented CLI batch mode

```
./nonSUSYorbifolder script <commandfile>
```

Runs the command list from `<commandfile>` non-interactively via
`CPrompt::StartPrompt(commandfile, stop_when_file_done=true)`, prints "Script
executed successfully!" to stdout, and **writes the actual command
transcript + results to `result_<commandfile>` in the CWD**, not to stdout.
Process exits cleanly (exit code 0). This is the one to parse.

### orbifolder (SUSY) — no CLI batch flag, but the same batch capability exists in the library

`main.cpp` only handles `argc==1` (interactive) and `argc==2` (load a single
model file then go interactive); there is no `script` subcommand wired up.
However `CPrompt::StartPrompt(ifilename, stop_when_file_done, online_mode)` has
the identical signature and behavior as in nonSUSYorbifolder — it's just not
exposed via `argv`. The interactive command `load program(<commandfile>)` runs
a script instead.

**Working non-interactive recipe (no upstream patching needed):**

```bash
printf 'load program(<commandfile>)\nyes\n' | ./orbifolder > output.txt
```

- The trailing `<commandfile>` must end with an `exit` command.
- `exit` triggers an interactive-only confirmation ("Do you really want to
  quit? Type \"yes\" to quit or \"no\" to continue.") that is read from the
  *raw stdin stream*, not from the command file — hence the `yes` sent as a
  second line on stdin, after the `load program(...)` line.
- Without the trailing `exit`/`yes`, the process does not exit on stdin EOF —
  it spins re-printing the prompt indefinitely. **The process runner in
  `src/core/` must always append `exit` to the generated command file and feed
  `"load program(<file>)\nyes\n"` on stdin**, and should still enforce a
  timeout as defense in depth.
- Unlike nonSUSYorbifolder, orbifolder's output (including the full command
  transcript) goes to **stdout**, not a side file.

This is the one architectural wrinkle vs. the original plan, but it does not
invalidate the subprocess approach: no source patching or custom `main.cpp` is
required, just a different invocation recipe per backend. `src/core/` should
abstract this behind a common "run a command script, get back the transcript
text" function, with `src/susy/` and `src/nonsusy/` supplying the
backend-specific invocation (stdin-piped vs. `script` argv + side-file read)
and cleanup (delete the `result_*` file after reading, for nonSUSYorbifolder).

## Command language (CPrompt)

Man pages ship for nonSUSYorbifolder under `doc/{main,model,spectrum,labels,
orbidir,vev-config}/*.man` (SUSY orbifolder ships no `.man` pages, but the
command language is effectively the same — same `cprompt.cpp` command tables
minus the non-SUSY additions). Key commands used for fixtures:

```
load orbifolds(<file>)        # load model(s) from a model-definition file
cd <Label>                    # enter an orbifold's directory
cd spectrum / cd model / cd "gauge group" / cd vev-config / cd couplings
print summary                 # (in cd spectrum) scalar+fermion massless spectrum,
                               # reps and U(1) charges, under current vev-config
print twist / print shift / print Wilson lines   # (in cd model)
print gauge group             # (in cd "gauge group")
exit                          # requires interactive "yes" confirmation
```

`print summary` supports modifiers: `with labels`, `of sectors`, `of sector
T(k,m,n)`, `of fixed points`, `no U1s`. A `couplings` subdirectory exists in
the command tree (`cd couplings`) but is undocumented (no `.man` page) —
needs interactive exploration in Phase 3 when building the coupling parser.

Model definition file format (used by `load orbifolds(...)`), shared by both
tools:

```
begin model
Label:<name>
SpaceGroup:Geometry/Geometry_<PointGroup>_<i>_<j>.txt
Lattice:E8xE8            # or SO32
Shifts and Wilsonlines:
<16 rationals: shift V_1>
<16 rationals: shift V_2, only for ZMxZN>
<16 rationals: W_1>
...
<16 rationals: W_6>
end model
```

Point-group-compatible `Geometry_*.txt` space-group files ship under
`Geometry/` in both repos (same file set/format).

## Sample output captured

Saved to `test/fixtures/`:
- `fixtures/nonsusy/{modelZ3_1_1.txt,z3_1_1_commands.txt,z3_1_1_summary.txt}` —
  nonSUSYorbifolder `script` mode output (`result_commands.txt` renamed).
- `fixtures/susy/{modelMSSM0.txt,mssm0_commands.txt,mssm0_summary.txt}` —
  orbifolder stdin-piped batch output, reproduced from a single extracted
  model out of the shipped 77-model Z3xZ3 example file.

Both capture: `print summary` (gauge group line + scalar/fermion rows with
representations and U(1) charge vectors), `print twist`, `print shift`,
`print Wilson lines` (nonSUSY only) / `print gauge group`.

## Follow-up procedure for upstream version bumps

1. Re-run `autoreconf -fi && ./configure && make` (nonSUSYorbifolder) or just
   `./configure && make` (orbifolder) against the new tarball/checkout; diff
   `cprompt.cpp`'s `command_names_*` tables against the previous version to
   catch new/renamed commands.
2. Re-run the fixture-generating commands above and diff against
   `test/fixtures/` to catch output-format drift before it breaks the parser.
3. Check `ChangeLog`/`AUTHORS` and the paper version referenced in `main.cpp`'s
   startup banner for the new version string.
