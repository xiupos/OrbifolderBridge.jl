# Upstream Notes

Findings on `orbifolder`/`nonSUSYorbifolder` from the initial investigation (2026-08-17),
covering how the two upstream C++ tools are built and driven, and what output they produce.
This is the basis for the subprocess-driven design (`src/core/`).

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
T(k,m,n)`, `of fixed points`, `no U1s`. With `with labels`, each spectrum row
gets one field label per copy appended after the charges (e.g. `F_1`, or for
a multiplicity-9 row, nine space-separated labels `F_18 F_20 F_22 ...`) —
useful for cross-referencing `couplings` output against individual fields.

Phase 1 uses two additional spectrum commands, verified against orbifolder
1.2.1 and nonSUSYorbifolder commit
`c917adea59b788872ac00bc41239dd791afc4ff1` for the 2026-08-24 fixtures:

```
print(*) with internal information
print summary of fixed points with labels
```

The first prints one block per individual field. In both backends it includes
the active field label, the constructing-element sector and six translation
coefficients, representation and U(1) charges, right-moving momentum,
`internalIndex`, and a zero-based `field no.`. The latter is independent of the
active display-label scheme and is used as `FieldID`. SUSY output uses sector
coordinates `(k,l)`; non-SUSY output uses `(k,m,n)`. Depending on the Geometry
file, the field block also prints `space group charges` and `R charges`.

The fixed-point summary supplies a fixed-point/fixed-brane label, constructing
translation, 16D `V_loc`, and the field labels at that localization. Joining it
to the individual blocks by field label gives localization while retaining the
backend field number as identity. The parser verifies that the translation
agrees on both sides and that individual fields reproduce every grouped
summary multiplicity.

## Model generation, classification, and inequivalence

Both supported backends implement:

```
create random orbifold from(Label) if(SM PS SU5 inequivalent 3generations)
    save to(models.txt) #models(10) use(1,1,0,0,0,0,0,0)
load orbifolds(candidates.txt) inequivalent
save orbifolds(representatives.txt)
```

The eight `use` entries denote two compactification-shift slots and six Wilson
lines; `1` inherits and `0` randomizes. Internally nonSUSYorbifolder has an
additional leading Witten-shift entry fixed to `true`, so its eight command
entries are stored at indices 1--8 rather than 0--7. The non-SUSY model-file
format consequently contains three shifts plus six Wilson lines, whereas the
SUSY format contains two shifts plus six Wilson lines.

`analyze config Xgenerations` calls the same `CAnalyseModel::AnalyseModel`
predicate used by generation filters. It checks SM, Pati--Salam, and SU(5)
embeddings, net generation count, and the corresponding vector-like spectrum
condition, creating `SMConfig*`, `PSConfig*`, or `SU5Config*` configurations
on success. `print anomaly info` reports the upstream anomaly calculation and
ends successful examples with `All anomalies are universal`.

SUSY 1.2.1 additionally accepts `compare #couplings of order(X)`, for
`X >= 3`, when generating or loading inequivalent models. non-SUSY 1.0 has no
equivalent option. Both programs seed `CRandomModel` with `srand(time(NULL))`;
the command language exposes no seed. Generated searches are therefore not
bitwise replayable from a request alone.

Random generation starts an upstream child process. Its process identifier is
an implementation detail and is redacted from typed bridge results. The bridge
follows the generation command with upstream's internal `wait(1)` so the child
completes before the isolated working directory is collected. The model-file
parser applies the mode-specific shift count and accepts only zero-valued
trailing vectors beyond the required data.

## VEV configurations

Both supported backends accept the same read-only configuration protocol:

```text
cd vev-config
print configs
use config(StandardConfig1)
print gauge group
```

`print configs` marks the current configuration with `->` and reports the
active/available field-label scheme. SUSY 1.2.1 additionally prints a `fields
with VEV` column; non-SUSY 1.0 omits that column when empty. `print gauge
group` encloses hidden factors in brackets after an observable-sector choice.
The bridge fixtures preserve both formats.

The mutable command tree advertises `create config`, `select observable
sector`, `vev(fields)`, and, in SUSY 1.2.1, `find unbroken gauge group`.
Spacing and backend availability differ for these operations, and numerical
VEV values are absent from `print configs`. Until successful fixed-VEV
assignment is fixture-tested in both backends, mutation remains in the
raw-command escape hatch instead of a partially reliable typed API.

## Couplings (`cd couplings`) — explored but not yet parsed

A `couplings` subdirectory exists in the command tree but ships no `.man`
page. `dir`/`help` inside it list:

```
print ...
create coupling(fields)            optional: allowed fields(...)
remove vanishing couplings
find(fields)                       list allowed couplings involving fields
find effective(fields)             same, effective couplings only
load couplings(Filename) / save couplings(Filename)
mass matrix(A B)
auto create mass matrix(A B)
```

`fields` are referenced by the `with labels` names (`F_1`, `F_2`, ...).
Calling `find(F_1 F_2)` directly after loading a model returns `W = 0` —
`find` appears to search only couplings that were previously registered via
`create coupling(...)`, not compute them from scratch on demand. Working out
the exact create/find/save protocol (and the resulting output grammar for
non-trivial `W`) needs more dedicated exploration than fits in Phase 3's
budget; the gauge group / spectrum / twist / shift / Wilson line parsers in
`src/core/parsers.jl` are solid and fixture-tested, but coupling parsing is
deferred to a follow-up increment.

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

The checked-in parser fixtures currently target `orbifolder` 1.2.1 and
`nonSUSYorbifolder` 1.0. These are also the only versions accepted by the
runtime compatibility table.

1. Re-run `autoreconf -fi && ./configure && make` (nonSUSYorbifolder) or just
   `./configure && make` (orbifolder) against the new tarball/checkout; diff
   `cprompt.cpp`'s `command_names_*` tables against the previous version to
   catch new/renamed commands.
2. Re-run the fixture-generating commands above and diff against
   `test/fixtures/` to catch output-format drift before it breaks the parser.
3. Check `ChangeLog`/`AUTHORS` and the paper version referenced in `main.cpp`'s
   startup banner for the new version string.
4. Add the new version to the compatibility table only after all SUSY or
   non-SUSY parser fixtures and real-backend smoke tests pass.
