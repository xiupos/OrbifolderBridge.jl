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
@structural_equality GaugeGroup

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
@structural_equality SpectrumField

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
@structural_equality Spectrum

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
@structural_equality FieldID

"""
    Sector

Untwisted or twisted sector coordinates exactly as reported by the backend.
SUSY orbifolder uses two coordinates `(k,l)`, while nonSUSYorbifolder uses
three `(k,m,n)` coordinates (including its Witten-twist coordinate).
"""
struct Sector
    coordinates::Vector{Int}
end
@structural_equality Sector

"""A constructing space-group element as reported by upstream."""
struct SpaceGroupElement
    sector::Sector
    translation::Vector{Rational{Int}}
end
@structural_equality SpaceGroupElement

"""One upstream-listed Geometry file compatible with a point group."""
struct SpaceGroupInfo
    backend::Symbol
    index::Int
    point_group_orders::Vector{Int}
    lattice_label::String
    additional_label::String
    geometry_file::String
end
@structural_equality SpaceGroupInfo

"""Metadata reported by upstream for the selected space group."""
struct SpaceGroupMetadata
    backend::Symbol
    point_group_orders::Vector{Int}
    lattice_label::String
    additional_label::String
    geometry_file::String
    generators::Vector{SpaceGroupElement}
end
@structural_equality SpaceGroupMetadata

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
@structural_equality FieldLocalization

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
@structural_equality DetailedField

"""
    DetailedSpectrum

Both views of a massless spectrum: `summary` preserves upstream grouping and
multiplicities, while `fields` contains one [`DetailedField`](@ref) per state.
"""
struct DetailedSpectrum
    summary::Spectrum
    fields::Vector{DetailedField}
end
@structural_equality DetailedSpectrum

"""
    Localization

A fixed point or fixed brane, identified by its complete constructing element,
with its exact local shift and stable field identifiers.
"""
struct Localization
    label::String
    constructing_element::SpaceGroupElement
    local_shift::Vector{Rational{Int}}
    fields::Vector{FieldID}
end
@structural_equality Localization

"""Upstream local shift and detailed states at one localization."""
struct LocalGaugeData
    localization::Localization
    fields::Vector{DetailedField}
end
@structural_equality LocalGaugeData

"""
    Twist

The twist vector(s) \$v_1\$ (and \$v_2\$, for \$\\mathbb{Z}_M \\times \\mathbb{Z}_N\$
point groups) of the orbifold's point group, as 4D vectors (`print twist`).
"""
struct Twist
    vectors::Vector{Vector{Rational{Int}}}
end
@structural_equality Twist

"""
    ShiftVector

One 16D shift vector \$V_i\$ (`print shift`), embedded in the \$E_8 \\times E_8\$
(or \$\\mathrm{SO}(32)\$) root lattice.
"""
struct ShiftVector
    label::String
    vector::Vector{Rational{Int}}
end
@structural_equality ShiftVector

"""
    WilsonLine

One 16D Wilson line \$W_i\$ (`print Wilson lines`).
"""
struct WilsonLine
    label::String
    vector::Vector{Rational{Int}}
end
@structural_equality WilsonLine

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
@structural_equality WilsonLines

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
@structural_equality VEVConfigurationRef

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
@structural_equality VEVConfigurationSummary

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
@structural_equality GaugeSector

"""
    VEVAssignment(field, value)

A deterministic numerical VEV assignment to an individual [`FieldID`](@ref).
The supported SUSY command language stores VEVs as floating-point values and
does not expose a weight-component selector. Random assignments are
intentionally not represented.
"""
struct VEVAssignment
    field::FieldID
    value::Float64

    function VEVAssignment(field::FieldID, value::Real)
        converted = Float64(value)
        isfinite(converted) || throw(ArgumentError("VEV values must be finite"))
        return new(field, converted)
    end
end
@structural_equality VEVAssignment

"""
    FieldVEV

A numerical VEV read back from upstream, connected to both its stable `field`
identity and the active configuration-dependent `label`.
"""
struct FieldVEV
    field::FieldID
    label::String
    value::Float64
end
@structural_equality FieldVEV

"""
    VEVConfigurationSpec

A replayable description of a derived VEV configuration. `nothing` preserves
the base configuration's observable non-abelian or U(1) selection; an empty
vector selects none. Fixed `assignments` and `recompute_unbroken_group` require
the SUSY backend.
"""
struct VEVConfigurationSpec
    configuration::VEVConfigurationRef
    base::VEVConfigurationRef
    observable_nonabelian::Union{Nothing,Vector{Int}}
    observable_u1::Union{Nothing,Vector{Int}}
    assignments::Vector{VEVAssignment}
    recompute_unbroken_group::Bool
end
@structural_equality VEVConfigurationSpec

function VEVConfigurationSpec(;
    name::AbstractString,
    base::VEVConfigurationRef = VEVConfigurationRef("TestConfig1"),
    observable_nonabelian::Union{Nothing,AbstractVector{<:Integer}} = nothing,
    observable_u1::Union{Nothing,AbstractVector{<:Integer}} = nothing,
    assignments::AbstractVector{VEVAssignment} = VEVAssignment[],
    recompute_unbroken_group::Bool = !isempty(assignments),
)
    nonabelian = observable_nonabelian === nothing ? nothing : Int.(observable_nonabelian)
    u1 = observable_u1 === nothing ? nothing : Int.(observable_u1)
    for (description, indices) in (("observable_nonabelian", nonabelian), ("observable_u1", u1))
        indices === nothing && continue
        all(>(0), indices) || throw(ArgumentError("$description indices must be positive"))
        length(unique(indices)) == length(indices) ||
            throw(ArgumentError("$description indices must be unique"))
    end
    fields = getfield.(assignments, :field)
    length(unique(fields)) == length(fields) ||
        throw(ArgumentError("each field may have at most one VEV assignment"))
    return VEVConfigurationSpec(
        VEVConfigurationRef(name),
        base,
        nonabelian,
        u1,
        collect(assignments),
        recompute_unbroken_group,
    )
end

"""
    VEVConfigurationResult

Materialized configuration data returned by
[`materialize_vev_configuration`](@ref). `resolution_transcript` records the
base-field lookup and `transcript` records configuration construction and
inspection. `detailed_spectrum` is `nothing` when a non-abelian factor is
hidden because upstream folds that representation's dimension into summary
multiplicities, which cannot be assigned unambiguously to one `FieldID`.
"""
struct VEVConfigurationResult
    specification::VEVConfigurationSpec
    configuration::VEVConfigurationSummary
    assignments::Vector{FieldVEV}
    gauge_sector::GaugeSector
    spectrum::Spectrum
    detailed_spectrum::Union{Nothing,DetailedSpectrum}
    backend::BackendInfo
    resolution_transcript::String
    transcript::String
end
@structural_equality VEVConfigurationResult

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

"""
    CouplingRequest(fields; allowed_fields = nothing)

A request for upstream to test and register one coupling monomial. `fields`
contains the stable identities of its factors and must have order at least
three. `allowed_fields`, when present, restricts the fields upstream may use
while applying its coupling-selection rules.
"""
struct CouplingRequest
    fields::Vector{FieldID}
    allowed_fields::Union{Nothing,Vector{FieldID}}
end
@structural_equality CouplingRequest

function CouplingRequest(
    fields::AbstractVector{FieldID};
    allowed_fields::Union{Nothing,AbstractVector{FieldID}} = nothing,
)
    length(fields) >= 3 || throw(ArgumentError("a coupling request must have order at least 3"))
    allowed = allowed_fields === nothing ? nothing : collect(allowed_fields)
    allowed === nothing || allunique(allowed) ||
        throw(ArgumentError("allowed_fields must not contain duplicates"))
    return CouplingRequest(collect(fields), allowed)
end

"""
    CouplingTerm

One coupling accepted by upstream. `fields` preserves the upstream factor
order and refers only to stable [`FieldID`](@ref)s.
"""
struct CouplingTerm
    fields::Vector{FieldID}
end
@structural_equality CouplingTerm

"""
    CouplingResult

Typed result of [`compute_couplings`](@ref). `terms` is empty when upstream
successfully finds no allowed coupling. The sanitized `transcript` and exact
upstream coupling-file `source` are retained for diagnostics and provenance.
"""
struct CouplingResult
    request::CouplingRequest
    configuration::VEVConfigurationRef
    terms::Vector{CouplingTerm}
    backend::BackendInfo
    transcript::String
    source::String
end
@structural_equality CouplingResult

"""
    CouplingSearchResult

Result of [`search_couplings`](@ref). `requests` records the candidate
monomials submitted through `max_order`; `involving` records the stable field
identities passed to upstream `find(...)`; and `terms` contains the matching
accepted couplings in the canonical saved-file representation.
"""
struct CouplingSearchResult
    requests::Vector{CouplingRequest}
    involving::Vector{FieldID}
    max_order::Int
    configuration::VEVConfigurationRef
    terms::Vector{CouplingTerm}
    backend::BackendInfo
    transcript::String
    source::String
end
@structural_equality CouplingSearchResult

"""
    UpstreamEffectiveCoupling

One monomial from SUSY orbifolder's effective superpotential. `fields` remain
dynamical, `vev_fields` were printed inside angle brackets, and `source`
identifies the registered ordinary coupling from which the term arose.
"""
struct UpstreamEffectiveCoupling
    source::CouplingTerm
    fields::Vector{FieldID}
    vev_fields::Vector{FieldID}
end
@structural_equality UpstreamEffectiveCoupling

"""
    EffectiveCouplingResult

Effective superpotential reported after replaying a declarative SUSY VEV
configuration and registering `requests`. Both ordinary `source_terms` and
expanded effective `terms` retain stable field identities.
"""
struct EffectiveCouplingResult
    specification::VEVConfigurationSpec
    requests::Vector{CouplingRequest}
    source_terms::Vector{CouplingTerm}
    terms::Vector{UpstreamEffectiveCoupling}
    backend::BackendInfo
    transcript::String
    source::String
end
@structural_equality EffectiveCouplingResult

"""
    CouplingParseError <: Exception

Thrown when a saved upstream coupling file is malformed, does not belong to
the supplied model, or refers to an unknown field. The complete `source` is
retained for diagnosis.
"""
struct CouplingParseError <: Exception
    message::String
    source::String
end

Base.showerror(io::IO, e::CouplingParseError) =
    print(io, "CouplingParseError: ", e.message)

"""
    CouplingExecutionError <: Exception

Thrown when the upstream child-coupling protocol does not report successful
completion or disagrees with its saved artifact. The complete `transcript` is
retained so an empty physical result is never confused with execution failure.
"""
struct CouplingExecutionError <: Exception
    message::String
    transcript::String
end

Base.showerror(io::IO, e::CouplingExecutionError) =
    print(io, "CouplingExecutionError: ", e.message)

"""
    MassMatrixRequest(rows, columns, couplings; max_order)

A reproducible request for an effective mass matrix. `rows` and `columns`
identify the external fields by stable field number, while `couplings` lists
the ordinary monomials that upstream must test and register. `max_order`
controls the explicit VEV products requested from upstream's matrix printer.
"""
struct MassMatrixRequest
    rows::Vector{FieldID}
    columns::Vector{FieldID}
    couplings::Vector{CouplingRequest}
    max_order::Int
end
@structural_equality MassMatrixRequest

function MassMatrixRequest(
    rows::AbstractVector{FieldID},
    columns::AbstractVector{FieldID},
    couplings::AbstractVector{CouplingRequest};
    max_order::Integer,
)
    isempty(rows) && throw(ArgumentError("mass-matrix rows must not be empty"))
    isempty(columns) && throw(ArgumentError("mass-matrix columns must not be empty"))
    allunique(rows) || throw(ArgumentError("mass-matrix rows must be unique"))
    allunique(columns) || throw(ArgumentError("mass-matrix columns must be unique"))
    isempty(couplings) && throw(ArgumentError("at least one coupling request is required"))
    allunique(couplings) || throw(ArgumentError("coupling requests must be unique"))
    max_order >= 1 || throw(ArgumentError("max_order must be at least 1"))
    overlap = intersect(rows, columns)
    isempty(overlap) || collect(rows) == collect(columns) || throw(ArgumentError(
        "row and column fields must be disjoint or identical",
    ))
    return MassMatrixRequest(collect(rows), collect(columns), collect(couplings), Int(max_order))
end

"""One upstream-derived VEV monomial in a mass-matrix entry."""
struct MassMatrixTerm
    source::CouplingTerm
    vev_fields::Vector{FieldID}
end
@structural_equality MassMatrixTerm

"""
    MassMatrixResult

An effective mass matrix reported by upstream. `entries[i, j]` is a vector
because several ordinary couplings may contribute to the same matrix entry.
Every contribution retains its ordinary source coupling and stable VEV fields.
"""
struct MassMatrixResult
    specification::VEVConfigurationSpec
    request::MassMatrixRequest
    rows::Vector{FieldID}
    columns::Vector{FieldID}
    entries::Matrix{Vector{MassMatrixTerm}}
    source_terms::Vector{CouplingTerm}
    transposed::Bool
    backend::BackendInfo
    transcript::String
    source::String
end
@structural_equality MassMatrixResult

"""A malformed or unsupported upstream mass-matrix display."""
struct MassMatrixParseError <: Exception
    message::String
    source::String
end

Base.showerror(io::IO, e::MassMatrixParseError) =
    print(io, "MassMatrixParseError: ", e.message)
