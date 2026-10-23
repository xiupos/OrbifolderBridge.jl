# Upstream Notes

Maintainer reference, not part of the published documentation: observed
behavior of the upstream `orbifolder` (SUSY) and `nonSUSYorbifolder`
programs that the bridge relies on. Unless stated otherwise, findings were
verified against orbifolder 1.2.1 and nonSUSYorbifolder 1.0. How the bridge
uses them is described in [`design.md`](design.md).

## Sources and binaries

- **orbifolder**: `https://orbifolder.hepforge.org/source/V1.2.1/orbifolder-1.2.1.tgz`.
- **nonSUSYorbifolder**: `https://github.com/StringsIFUNAM/nonSUSYorbifolder`.

`orbifolder_binary`/`orbifolder_geometry_dir` resolve the executables via
`OrbiFolder_jll`/`NonSUSYOrbiFolder_jll`, built by Yggdrasil recipes
(`JuliaPackaging/Yggdrasil#14471` and `#14999`) for Linux only. Each JLL bundles
the tool's `Geometry/` directory. Upstream instantiates
`std::complex<boost::rational<int>>`, which libc++ (used for macOS and FreeBSD
targets) cannot compile, so there are no macOS, FreeBSD, or Windows builds.

Both tools share the same `src/` layout and core classes (`CPrompt`,
`COrbifold`, `CSpectrum`, `CState`, ...); nonSUSYorbifolder adds non-SUSY mass
and GSO logic on top.

## Non-interactive execution

Both tools are built around an interactive REPL (`CPrompt`, GNU Readline) with
path-like navigation (`cd Label`, `cd spectrum`, `cd model`, ...). Their batch
entrypoints differ.

**nonSUSYorbifolder** has a CLI batch mode:

```
./nonSUSYorbifolder script <commandfile>
```

It prints "Script executed successfully!" to stdout and writes the command
transcript and results to `result_<commandfile>` in the working directory.

**orbifolder** has no `script` argument, but the interactive command
`load program(<commandfile>)` runs a script:

```bash
printf 'load program(<commandfile>)\nyes\n' | ./orbifolder > output.txt
```

- The command file must end with `exit`.
- `exit` asks "Do you really want to quit?" on raw stdin, not from the command
  file, hence the second `yes` line.
- Without `exit`/`yes` the process does not exit on stdin EOF; it re-prints the
  prompt indefinitely.
- The transcript goes to stdout.

## Command language

nonSUSYorbifolder ships man pages under `doc/{main,model,spectrum,labels,
orbidir,vev-config}/*.man`. orbifolder ships none, but its `cprompt.cpp`
command tables are the same minus the non-SUSY additions.

```
load orbifolds(<file>)        # load model(s) from a model-definition file
cd <Label>                    # enter an orbifold's directory
cd spectrum / cd model / cd "gauge group" / cd vev-config / cd couplings
print summary                 # (spectrum) massless spectrum under current vev-config
print twist / print shift / print Wilson lines   # (model)
print gauge group             # (gauge group)
print simple roots            # exact 16D roots, ordered by gauge factor
print U1 generators           # exact 16D generators, ordered as spectrum charges
exit                          # requires interactive "yes" confirmation
```

`print summary` accepts the modifiers `with labels`, `of sectors`,
`of sector T(k,m,n)`, `of fixed points`, and `no U1s`. With `with labels`,
each row gets one field label per copy after the charges (e.g. nine labels
`F_18 F_20 F_22 ...` for a multiplicity-9 row).

### Exact gauge data

`print simple roots` and `print U1 generators` print each vector as two groups
of eight rationals. Simple roots are concatenated in gauge-factor order;
factor boundaries follow from the reported Cartan ranks. U(1)
generators use the charge-column order, so when `print summary` reports the
first U(1) as anomalous, the first generator is the anomalous direction.

`CState::RecalculateU1Charges` computes each charge as the 16D Euclidean inner
product of the printed generator with a left-moving weight, so the generator
Gram matrix is exact intrinsic normalization data. No target normalization is
printed; the classification-specific targets in `CAnalyseModel` (e.g. `5/6`
for one hypercharge scheme) are not general metadata.

`CState` computes highest weights in Dynkin labels internally, but no supported
prompt command prints them, and the `left-moving p_sh` field of `PrintStates`
is empty in batch output. Representations are therefore available only as
signed dimensions.

### Individual fields and localization

```
print(*) with internal information
print summary of fixed points with labels
```

The first prints one block per field (verified for nonSUSYorbifolder at commit
`c917adea59b788872ac00bc41239dd791afc4ff1`): active label, constructing-element
sector and six translation coefficients, representation, U(1) charges,
right-moving momentum, `internalIndex`, and a zero-based `field no.` that does
not depend on the label scheme. Sectors are `(k,l)` in SUSY and `(k,m,n)` in
non-SUSY. Depending on the Geometry file, blocks also print
`space group charges` and `R charges`. For an N=1 model the unqualified
`print(*)` shows left-chiral fields only; `print(*) vector with internal
information` shows gauge bosons, whose representation carries an `_adj` suffix
(e.g. `8_adj`).

The second prints, per fixed point or fixed brane, its label, constructing
translation, 16D `V_loc`, and the labels of the fields localized there.

The SUSY source has a `print local matter(...)` branch, but its body is
commented out in 1.2.1, so upstream offers no local gauge group.

## Model files and Geometry

`COrbifoldGroup::LoadOrbifoldGroup` always reads a fixed number of shift
vectors before the six Wilson lines, regardless of point group. A missing or
reordered shift line therefore misassigns every following vector rather than
failing to load.

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

nonSUSYorbifolder reads three: the Witten Z_2 embedding first,
then the same two compactification shifts.

Both `Geometry/` trees contain the same 138 filenames, but nonSUSYorbifolder
prepends the Witten `Z_2` coordinate, so its sectors and constructing elements
have three point-group coordinates instead of two.

In the model directory, `print available space groups` lists the staged
Geometry files matching the loaded point-group orders; `print point group` and
`print space group` print the root-lattice label and generators, with `(k,l)`
or `(k,m,n)` sectors followed by six translation coefficients.

## Model generation and classification

```
create random orbifold from(Label) if(SM PS SU5 inequivalent 3generations)
    save to(models.txt) #models(10) use(1,1,0,0,0,0,0,0)
load orbifolds(candidates.txt) inequivalent
save orbifolds(representatives.txt)
```

The eight `use` entries cover two compactification shifts and six Wilson
lines; `1` inherits and `0` randomizes. nonSUSYorbifolder stores them at
indices 1–8 behind an internal Witten-shift entry fixed to `true`.

`analyze config Xgenerations` uses the same `CAnalyseModel::AnalyseModel`
predicate as the generation filters: it checks SM, Pati–Salam, and SU(5)
embeddings, the net generation count, and vector-like exotics, and creates
`SMConfig*`, `PSConfig*`, or `SU5Config*` configurations on success.
`print anomaly info` ends successful examples with `All anomalies are
universal`.

SUSY 1.2.1 also accepts `compare #couplings of order(X)` (`X >= 3`) when
generating or loading inequivalent models; non-SUSY 1.0 does not.

Both programs seed `CRandomModel` with `srand(time(NULL))` and expose no seed,
so generated searches cannot be replayed bitwise. Random generation runs in a
forked child process; `wait(1)` blocks until it completes.

## VEV configurations

```text
cd vev-config
print configs
use config(StandardConfig1)
print gauge group
```

`print configs` marks the current configuration with `->` and reports the
field-label scheme. SUSY 1.2.1 also prints a `fields with VEV` column, which
non-SUSY 1.0 omits when empty. After an observable-sector selection,
`print gauge group` encloses hidden factors in brackets.

Both backends implement `create config(...) from(...)` and `select observable
sector: ...`. A configuration exists only for the lifetime of one process.

When a non-abelian factor is hidden, upstream drops it from the spectrum
representation and multiplies the row multiplicity by its dimension, so
individual field numbers no longer match grouped multiplicities one-for-one.

SUSY 1.2.1 additionally implements `vev(F_1)=1.0` and `find unbroken gauge
group`; non-SUSY 1.0 implements neither.

- Whitespace between `)` and `=` makes the VEV command unrecognized.
- Success prints `Vev of field "F_1" set to 1.00`; `print configs` lists
  `<F_1>`, and internal field output contains `vev : 1.00`.
- The VEV is always written to component zero of the field's left-moving
  weight vector; no component selector exists.

## Couplings

`cd couplings` has no man page. Its `help` lists:

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

Only SUSY 1.2.1 implements these; the non-SUSY 1.0 table for this directory
contains only `dir`.

Fields are referenced by their active `with labels` names. `create
coupling(...)` needs at least three factors and forks a child process.
`find(...)` does not compute couplings; it filters those already registered.

```text
create coupling(F_1 F_11 F_13)
wait(1)
print superpotential
save couplings(couplings.txt)
```

For `MSSM0` this prints `W = F_1 F_11 F_13`. The saved file has nine header
lines (lattice, two shifts, six Wilson lines) followed by rows of zero-based
field numbers; here the row is `11 37 39`, matching `field no.`. An empty
result is the header with no rows.

Known defects and hazards in 1.2.1:

- With several `create coupling(...)` before one `wait(1)`, `waiting done.`
  can print before every child result is loaded; a later command then picks up
  the lagging child. Put `wait(1)` immediately after each creation.
- `save couplings(Filename) of order(X)` is broken: `CPrompt` calls
  `FindParameterType2` on the filename rather than on the option string.
- `remove vanishing couplings` asks `Coupling zero? (y/n)` on raw stdin for
  representation patterns missing from its process-local tables, so it is not
  batchable in general.

With a nonzero VEV, `print effective superpotential` and `find effective(...)`
write VEV fields in angle brackets, e.g. `W_eff = F_1 F_11 <F_13>` after
`vev(F_13)=1.0`. `CPrint` groups terms with the same non-VEV fields as a
parenthesized `+`-separated sum of VEV products.

### Mass matrices

`mass matrix(A B)` builds `A_i M_ij B_j` from effective couplings registered
in the active configuration and stores it as a process-local numbered matrix.
`print mass matrix(1) max order(X)` prints explicit products such as `<n_1>`
up to order `X`; beyond that, nonzero entries print as `s` or `s^N`. Zero
entries print as `0`; multiple contributions are joined by ` + `.

Each entry lists the source coupling's remaining fields, and only when all of
them have nonzero VEVs. With at least ten columns and fewer rows than columns,
upstream transposes the matrix; the printed header gives the actual
orientation and dimensions. `auto create mass matrix(...)` additionally
searches singlet insertions internally.

A verified example on `MSSM0` relabels fields 11 and 37 as `A_1` and `B_1`,
assigns a VEV to field 39, registers the cubic coupling, and prints a `1 x 1`
entry `<n_1>`.

## Combined read-only sequences

After one model load, the model, gauge-group, spectrum, and Geometry print
commands can be issued in sequence in both backends, and changing directory
does not reset the selected VEV configuration. The combined transcript keeps
the same grammar as the individual captures. Coupling creation, mass matrices,
generation, and configuration creation start child jobs, write side files, or
mutate process-local state, so they need their own command sequences.

## Fixtures

Captured transcripts live under `test/fixtures/susy/` and
`test/fixtures/nonsusy/`. SUSY fixtures use `MSSM0`, extracted from the
shipped 77-model Z3xZ3 example file; non-SUSY fixtures use `Z3_1_1` from the
upstream guide.

## Upstream version bumps

The fixtures and runtime compatibility table currently accept only orbifolder
1.2.1 and nonSUSYorbifolder 1.0.

1. Update the Yggdrasil recipe and wait for the new
   `OrbiFolder_jll`/`NonSUSYOrbiFolder_jll` version to be registered.
2. Diff `cprompt.cpp`'s `command_names_*` tables against the previous version,
   and check `ChangeLog` and the `main.cpp` startup banner for the version
   string.
3. Raise the JLL compat bound in `Project.toml`, regenerate the fixtures with
   the new binaries, and diff against `test/fixtures/` for format drift.
4. Add the new version to the compatibility table only after all parser
   fixtures and real-backend tests pass.
