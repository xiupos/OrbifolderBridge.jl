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
print simple roots            # exact 16D roots, ordered by gauge factor
print U1 generators           # exact 16D generators, ordered as spectrum charges
exit                          # requires interactive "yes" confirmation
```

The two exact gauge commands were verified with orbifolder 1.2.1 and
nonSUSYorbifolder 1.0. Each vector is printed as two groups of eight rational
entries. Simple roots are concatenated in gauge-factor order; the bridge
recovers factor boundaries from the reported Cartan ranks. U(1) generators
use the charge-column order. When `print summary` states that the first U(1)
is anomalous, its first printed generator is therefore the exact anomalous
direction.

The command protocol does not print separate U(1) target-normalization
constants. The bridge constructs the exact Gram matrix intrinsic to the
printed basis without attributing a classification-specific target to it.
Likewise,
the group-theory implementation internally computes Dynkin labels and highest
weights, but the supported prompt command tables expose neither value. Exact
representation labels therefore remain unavailable without changing
upstream; dimension-based conversion stays an explicit fallback.

Source inspection establishes the part of the normalization convention that
is common to all computations: `CState::RecalculateU1Charges` computes each
charge as the 16-dimensional Euclidean inner product of the printed generator
with a representative left-moving weight. Consequently the generator Gram
matrix, its inverse charge metric, and squared lengths are exact intrinsic
normalization data. `CAnalyseModel` also contains optional target lengths for
particular classification schemes (for example `5/6` for one hypercharge
scheme), but those targets are neither general gauge-basis metadata nor
available from the supported prompt output.

Although `CState` internally determines highest weights in Dynkin labels
before mapping them to printed signed dimensions, `PrintStates` does not print
those labels. Its nominal `left-moving p_sh` field is empty for the supported
batch fixtures because the representative weight is not retained there.
OrbifolderBridge can therefore validate and convert exact labels supplied by a
future upstream source, while tagging current dimension inversion explicitly
as a fallback.

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

Both backends implement `create config(...) from(...)` and `select observable
sector: ...`. These operations are replayed from a
`VEVConfigurationSpec` because an upstream configuration exists only for the
lifetime of one process.

SUSY 1.2.1 additionally implements:

```text
vev(F_1)=1.0
find unbroken gauge group
print(*) with internal information
```

Whitespace between the closing parenthesis and `=` makes the VEV command
unrecognized. Successful assignment prints `Vev of field "F_1" set to 1.00`,
`print configs` lists `<F_1>`, and internal field output contains `vev :
1.00`. The command always writes component zero of the field's left-moving
weight vector; no component selector is exposed. non-SUSY 1.0 implements
neither VEV assignment nor unbroken-group recomputation.

After a non-abelian factor is hidden, upstream omits that factor from the
spectrum representation and multiplies the row multiplicity by its printed
dimension. Individual field numbers no longer reproduce those projected
multiplicities one-for-one. The bridge retains the grouped spectrum but does
not construct a misleading detailed spectrum for that case.

## Couplings (`cd couplings`)

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

These commands are implemented only by SUSY orbifolder 1.2.1. The non-SUSY
1.0 command table for this directory contains only `dir`; it has no Yukawa-
coupling implementation.

### Mass matrices

`mass matrix(A B)` constructs `A_i M_ij B_j` from effective couplings already
registered in the active VEV configuration and saves it as a process-local
numbered matrix. `print mass matrix(1) max order(X)` prints explicit products
such as `<n_1>` through order `X`; without a sufficient maximum it replaces a
nonzero entry by `s` or `s^N`. Zero entries print as `0`, and several
contributions are separated by ` + `.

The constructor removes the selected row and column fields from each source
coupling and prints the remaining fields only when all have nonzero VEVs. If
there are at least ten columns and fewer rows than columns, it automatically
transposes the matrix. The printed header gives the actual label orientation
and dimensions and must therefore be treated as data rather than decoration.

A verified nonempty batch sequence on `MSSM0` relabels stable fields 11 and 37
as `A_1` and `B_1`, assigns a VEV to field 39, registers the corresponding
cubic coupling, and prints a `1 x 1` entry `<n_1>`. Matrix commands are absent
from non-SUSY 1.0. The broader `auto create mass matrix(...)` command searches
additional singlet insertions internally; the bridge initially exposes only
explicit coupling candidates so the requested search space is reproducible.

`fields` are referenced by the active `with labels` names (`F_1`, `F_2`,
...). `create coupling(...)` requires at least three factors and forks an
upstream child process. A deterministic batch script must follow it with
`wait(1)` before reading or saving the registered result. `find(...)` does not
calculate new couplings: it filters the configuration's already registered
couplings. A verified non-empty sequence is:

```text
create coupling(F_1 F_11 F_13)
wait(1)
print superpotential
save couplings(couplings.txt)
```

For the `MSSM0` fixture this prints `W = F_1 F_11 F_13` and reports one
created coupling. The saved file contains nine header lines—the lattice, two
shifts, and six Wilson lines—followed by rows of zero-based internal field
numbers. The corresponding row is `11 37 39`, exactly matching the `field
no.` values used by the bridge's `FieldID`. An empty allowed set is a valid
header with no following rows.

Although multiple `create coupling(...)` children can be launched before one
`wait(1)`, SUSY 1.2.1 can print `waiting done.` before every child result has
been loaded into the configuration; a later command then collects the lagging
child. Reproducible scripts must place `wait(1)` immediately after each
creation. `find(fields)` then filters the registered collection. The documented
`save couplings(Filename) of order(X)` option is defective in 1.2.1:
`CPrompt` calls `FindParameterType2` on the extracted filename rather than on
the trailing option string. The bridge limits the explicit requests sent to
upstream instead of relying on this filter.

`remove vanishing couplings` is not safely batchable in general. When it sees
a representation pattern not present in its process-local known-zero/nonzero
tables, it asks `Coupling zero? (y/n)` on raw stdin. OrbifolderBridge therefore
does not invoke it or replace that physical decision with Julia logic.

With a nonzero VEV, `print effective superpotential` and `find effective(...)`
write angle-bracketed VEV factors. For example, assigning `vev(F_13)=1.0`
after registering `F_1 F_11 F_13` prints:

```text
W_eff = F_1 F_11 <F_13>
```

When several ordinary terms have the same non-VEV fields, `CPrint` groups the
VEV products in parentheses separated by `+`. The bridge parses and expands
this presentation, then verifies each monomial against the native saved
ordinary coupling set.

Model definition file format (used by `load orbifolds(...)`), shared by both
tools but with different shift counts. `COrbifoldGroup::LoadOrbifoldGroup`
always reads exactly the shift vectors below before the six Wilson lines,
regardless of point group: a missing or reordered shift line desynchronizes
every following Wilson line instead of failing to load.

SUSY orbifolder reads two shifts:

```
begin model
Label:<name>
SpaceGroup:Geometry/Geometry_<PointGroup>_<i>_<j>.txt
Lattice:E8xE8            # or Spin32
Shifts and Wilsonlines:
<16 rationals: shift V_1>
<16 rationals: shift V_2, zero-filled for a cyclic point group>
<16 rationals: W_1>
...
<16 rationals: W_6>
end model
```

nonSUSYorbifolder reads three shifts: the Witten ``\mathbb Z_2`` embedding
always comes first, ahead of the same two compactification shifts:

```
begin model
Label:<name>
SpaceGroup:Geometry/Geometry_<PointGroup>_<i>_<j>.txt
Lattice:E8xE8            # or Spin32
Shifts and Wilsonlines:
<16 rationals: Witten Z_2 embedding>
<16 rationals: shift V_1>
<16 rationals: shift V_2, zero-filled for a cyclic point group>
<16 rationals: W_1>
...
<16 rationals: W_6>
end model
```

Point-group-compatible `Geometry_*.txt` space-group files ship under
`Geometry/` in both repos. The supported trees each contain the same 138
filenames, but their contents and grammar differ: nonSUSYorbifolder prepends
the Witten `Z_2` twist coordinate, so its sectors and constructing elements
have three point-group coordinates where SUSY orbifolder has two.

Both prompts implement `print available space groups`, `print point group`,
and `print space group` in the model directory. The first scans the staged
`Geometry/` directory for the loaded point-group orders and prints an indexed
table of compactification lattice labels, optional additional labels, and
filenames. `print space group` prints the compactification root-lattice label
and generators. The latter use `(k,l)` sectors in SUSY and `(k,m,n)` sectors
in non-SUSY, followed by six translation coefficients.

The SUSY source contains a `print local matter(...)` command branch, but its
body is commented out in 1.2.1; it is not a usable source of a local gauge
group. Phase 8 therefore retains the `V_loc` printed by the fixed-point
summary and the states joined to it, without deriving a gauge group in Julia.

## Integrated read-only command sequences

The model, gauge-group, spectrum, and Geometry print commands can be issued
sequentially after one model load in both supported backends. Directory
changes do not invalidate the selected VEV configuration. Phase 9 therefore
groups requested `print twist`, `print shift`, `print Wilson lines`, `print
point group`, and `print space group` commands in the model directory; exact
gauge commands in the gauge-group directory; and summary/internal-field/fixed-
point commands in the spectrum directory. A selected configuration is applied
once before those groups.

Real-backend checks against SUSY 1.2.1 and non-SUSY 1.0 confirmed that this
combined transcript retains the same grammar as the smaller captured
transcripts. Coupling creation, mass matrices, generation, and configuration
materialization are not appended to this sequence: they start child jobs,
produce side files, or mutate process-local state and keep their specialized
execution protocols.

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
