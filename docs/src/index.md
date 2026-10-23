```@meta
CurrentModule = OrbifolderBridge
```

# OrbifolderBridge

Documentation for [OrbifolderBridge](https://github.com/xiupos/OrbifolderBridge.jl).

!!! warning "Experimental — no maintenance guarantee"
    This package is a temporary bridge and is **not registered** in the Julia General
    registry. It exists solely to expose the C++ `orbifolder`/`nonSUSYorbifolder` tools to
    OSCAR.jl users until (if ever) the functionality is integrated upstream. Expect breaking
    changes without notice. Do not depend on it in production code.

A Julia bridge to two C++ tools for constructing and analyzing heterotic string orbifold
compactifications:

- [**orbifolder**](https://orbifolder.hepforge.org/) (Nilles, Ramos-Sánchez, Vaudrevange,
  Wingerter, [arXiv:1110.5229](https://arxiv.org/abs/1110.5229)) — the supersymmetric
  heterotic orbifolder
- [**nonSUSYorbifolder**](https://github.com/StringsIFUNAM/nonSUSYorbifolder)
  (Escalante-Notario, Pérez-Martínez, Ramos-Sánchez, Vaudrevange,
  [arXiv:2504.20137](https://arxiv.org/abs/2504.20137)) — its non-SUSY fork

Both tools are driven as subprocesses (`mode = :susy` / `:nonsusy`): `OrbifolderBridge.jl`
writes a model file and a list of `CPrompt` commands, runs the appropriate binary in its own
temporary directory, and parses the text transcript back into Julia structs — optionally
further mapped onto genuine `Oscar.RootSystem`/`Oscar.WeightLatticeElem` objects for the gauge
group and matter representations.

**OrbifolderBridge supports Linux only.** `orbifolder`/`nonSUSYorbifolder` are installed
automatically as the `OrbiFolder_jll`/`NonSUSYOrbiFolder_jll` dependencies. Upstream does not
build on macOS, FreeBSD, or Windows.

## Installation

Add the package (development mode, since it is unregistered):

```julia
using Pkg
Pkg.develop(url="https://github.com/xiupos/OrbifolderBridge.jl")
```

## Quick start

```julia
using OrbifolderBridge

# A Z3 orbifold on the E8xE8 lattice (Geometry/Geometry_Z3_1_1.txt, point group Z3).
model = OrbifolderModel(;
    mode = :nonsusy,
    label = "Z3_1_1",
    point_group = "Z3_1_1",
    shift = (
        [0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0],
        [1//3, 1//3, -2//3, zeros(Int, 13)...],
    ),
)

spectrum = compute_spectrum(model)
println(spectrum.gauge_group)                 # GaugeGroup("TestConfig1", ["SO(10)","SU(3)","SO(16)"], 1)
println(length(spectrum.fields))               # 13

for f in spectrum.fields
    println(f.multiplicity, " × ", f.rep, "_", f.statistic, "  charges: ", f.charges)
end
```

Start with the [Overview](@ref), then use the task-oriented guide pages for
[Models and Geometry](@ref), [Spectra and Fields](@ref), [OSCAR Integration](@ref), and
[Consistency and Batch Workflows](@ref). Each page explains its concepts and workflow before
presenting the related public API.

## Known limitations

- Derived configurations and observable sectors are replayable on both
  backends; fixed VEV assignment and unbroken-group recomputation are
  available only with SUSY orbifolder.
- Explicitly requested ordinary superpotential couplings are available with
  SUSY orbifolder. The supported non-SUSY backend has no coupling engine;
  ordinary/effective coupling parsing and OSCAR polynomial conversion are
  therefore SUSY-only capabilities.
- [`find_weight_of_dimension`](@ref) resolves a representation's printed *dimension* to a
  weight via a bounded search over small Dynkin-label combinations. This covers every
  representation that actually appears in these models' output (fundamentals, adjoints,
  vectors, spinors, ...), but is not a fully general inverse of the Weyl dimension formula.

## Architecture

Each subprocess call runs in its own `mktempdir()`, so parallel calls ([`compute_spectra`](@ref)
etc.) never share files. Only the "launch binary, wait, capture text" step is parallelized via
`asyncmap`; parsing — and especially building OSCAR/GAP objects — is done sequentially
afterward, since GAP is not thread-safe.

## License

MIT for this bridge package. The upstream `orbifolder`/`nonSUSYorbifolder` tools, installed
through their JLL packages, are licensed under the GPL — see their respective repositories.
