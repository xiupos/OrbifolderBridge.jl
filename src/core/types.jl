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
    FieldID

Stable identity of an individual upstream field. `number` is the zero-based
`field no.` reported by `print(fields) with internal information`; unlike a
display label, it does not depend on the selected label scheme. A `FieldID` is
scoped to one orbifold model and backend field basis.
"""
struct FieldID
    number::Int
end

"""
    Sector

Untwisted or twisted sector coordinates exactly as reported by the backend.
SUSY orbifolder uses two coordinates `(k,l)`, while nonSUSYorbifolder uses
three `(k,m,n)` coordinates (including its Witten-twist coordinate).
"""
struct Sector
    coordinates::Vector{Int}
end

"""
    FieldLocalization

Localization of an individual field at an upstream fixed point or fixed
brane. `translation` is the six-component translational part of its
constructing element, and `local_shift` is the reported 16-dimensional
`V_loc`. `label` is upstream's fixed-point label, such as `"T54"` or `"U"`.
"""
struct FieldLocalization
    label::String
    translation::Vector{Rational{Int}}
    local_shift::Vector{Rational{Int}}
end

"""
    DetailedField

One individually identified massless field. Gauge quantum numbers use the
same conventions as [`SpectrumField`](@ref). `label` is configuration-dependent
metadata; cross-references should use `id`. `space_group_charges`, `r_charges`,
and `right_moving_momentum` are populated when upstream prints them.
"""
struct DetailedField
    id::FieldID
    label::String
    rep::Vector{Int}
    statistic::Symbol
    charges::Vector{Rational{Int}}
    multiplet_type::Symbol
    sector::Sector
    constructing_translation::Vector{Rational{Int}}
    localization::Union{Nothing,FieldLocalization}
    space_group_charges::Vector{Rational{Int}}
    r_charges::Vector{Rational{Int}}
    right_moving_momentum::Vector{Rational{Int}}
end

"""
    DetailedSpectrum

Both views of a massless spectrum: `summary` preserves upstream grouping and
multiplicities, while `fields` contains one [`DetailedField`](@ref) per state.
"""
struct DetailedSpectrum
    summary::Spectrum
    fields::Vector{DetailedField}
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

"""
    VEVConfigurationRef(label)

An explicit reference to an upstream VEV configuration. Configuration labels
end in a numeric suffix, for example `"StandardConfig1"` or `"SMConfig2"`.
Use this value in every configuration-dependent computation when reproducible
selection matters.
"""
struct VEVConfigurationRef
    label::String

    function VEVConfigurationRef(label::AbstractString)
        value = String(label)
        occursin(r"^[A-Za-z_]+[0-9]+$", value) || throw(ArgumentError(
            "VEV configuration labels must contain letters/underscores followed by a numeric suffix",
        ))
        return new(value)
    end
end

"""
    VEVConfigurationSummary

One row of upstream's `print configs` table. `active_label` is the selected
field-label scheme, `label_count` is the number available, and
`fields_with_vev` contains the active labels printed by upstream. The table
does not report numerical VEV values.
"""
struct VEVConfigurationSummary
    configuration::VEVConfigurationRef
    selected::Bool
    active_label::Int
    label_count::Int
    fields_with_vev::Vector{String}
end

"""
    GaugeSector

Observable/hidden partition of the gauge factors in one VEV configuration.
Indices refer to `gauge_group.nonabelian` and to the ordered U(1) factors,
respectively, and are one-based Julia indices.
"""
struct GaugeSector
    gauge_group::GaugeGroup
    observable_nonabelian::Vector{Int}
    hidden_nonabelian::Vector{Int}
    observable_u1::Vector{Int}
    hidden_u1::Vector{Int}
end

"""
    VEVConfigurationError <: Exception

Thrown when upstream rejects an explicit configuration selection. The full
raw `transcript` is retained for diagnosis.
"""
struct VEVConfigurationError <: Exception
    configuration::VEVConfigurationRef
    message::String
    transcript::String
end

Base.showerror(io::IO, e::VEVConfigurationError) =
    print(io, "VEVConfigurationError: ", e.message)

# These are plain value types (parsed data, not identity-bearing objects), so
# equality/hashing should be structural rather than Julia's default identity
# fallback for non-isbits structs.
for T in (
    :GaugeGroup, :SpectrumField, :Spectrum, :FieldID, :Sector, :FieldLocalization,
    :DetailedField, :DetailedSpectrum, :Twist, :ShiftVector, :WilsonLine, :WilsonLines,
    :VEVConfigurationRef, :VEVConfigurationSummary, :GaugeSector,
)
    @eval begin
        Base.:(==)(a::$T, b::$T) = all(getfield(a, f) == getfield(b, f) for f in fieldnames($T))
        Base.hash(a::$T, h::UInt) = hash(ntuple(i -> getfield(a, i), fieldcount($T)), hash($T, h))
    end
end
