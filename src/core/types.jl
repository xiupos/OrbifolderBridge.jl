"""
    GaugeGroup

The four-dimensional gauge group \$G = G_1 \\times \\dots \\times G_r \\times
\\mathrm{U}(1)^n\$ in a given vev-configuration, as reported by `print gauge
group` / the header line of `print summary`.

Fields:
- `config_label`: the vev-configuration label (e.g. `"TestConfig1"`)
- `nonabelian`: the non-abelian simple factors \$G_1,\\dots,G_r\$ in the order
  used by [`SpectrumField`](@ref)`.rep`, as printed (e.g. `["SO(10)", "SU(3)"]`)
- `n_u1`: the number \$n\$ of \$\\mathrm{U}(1)\$ factors
"""
struct GaugeGroup
    config_label::String
    nonabelian::Vector{String}
    n_u1::Int
end

"""
    SpectrumField

One row of massless spectrum output (`print summary`): a set of `multiplicity`
identical massless states, transforming in representation `rep` of
[`GaugeGroup`](@ref)`.nonabelian` (signed integers; negative values denote the
conjugate representation, e.g. `-16` for \$\\overline{16}\$) with U(1) charges
`charges`, tagged by upstream's one-letter `statistic` (e.g. `:s`/`:f` for
scalar/fermion in the non-SUSY orbifolder's default vev-configuration, `:l`
for left-chiral superfields in the SUSY orbifolder's).
"""
struct SpectrumField
    multiplicity::Int
    rep::Vector{Int}
    statistic::Symbol
    charges::Vector{Rational{Int}}
end

"""
    Spectrum

The massless spectrum (`print summary`) of an orbifold model in a given
vev-configuration.

Fields:
- `gauge_group`: the [`GaugeGroup`](@ref) the fields transform under
- `anomalous_tr_q`: \$\\operatorname{tr} Q_\\mathrm{anom}\$ for the first
  \$\\mathrm{U}(1)\$ factor, or `nothing` if none is anomalous
- `fields`: the [`SpectrumField`](@ref)s
"""
struct Spectrum
    gauge_group::GaugeGroup
    anomalous_tr_q::Union{Nothing,Float64}
    fields::Vector{SpectrumField}
end

"""
    Twist

The twist vector(s) \$v_1\$ (and \$v_2\$, for \$\\mathbb{Z}_M \\times \\mathbb{Z}_N\$
point groups) of the orbifold's point group, as 4D vectors (`print twist`).
"""
struct Twist
    vectors::Vector{Vector{Rational{Int}}}
end

"""
    ShiftVector

One 16D shift vector \$V_i\$ (`print shift`), embedded in the \$E_8 \\times E_8\$
(or \$\\mathrm{SO}(32)\$) root lattice.
"""
struct ShiftVector
    label::String
    vector::Vector{Rational{Int}}
end

"""
    WilsonLine

One 16D Wilson line \$W_i\$ (`print Wilson lines`).
"""
struct WilsonLine
    label::String
    vector::Vector{Rational{Int}}
end

"""
    WilsonLines

The six Wilson lines of an orbifold model (`print Wilson lines`), together
with the identifications and allowed orders imposed by the point group.

Fields:
- `lines`: the six [`WilsonLine`](@ref)s \$W_1,\\dots,W_6\$
- `identifications`: pairs of labels identified by the point group, e.g.
  `[("W_1","W_2"), ("W_3","W_4"), ("W_5","W_6")]`
- `orders`: the allowed order of each Wilson line, in the same order as `lines`
"""
struct WilsonLines
    lines::Vector{WilsonLine}
    identifications::Vector{Tuple{String,String}}
    orders::Vector{Int}
end
