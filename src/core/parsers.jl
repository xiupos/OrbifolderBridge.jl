const _GAUGE_GROUP_HEADER_RE =
    r"Gauge group in vev-configuration \"([^\"]*)\":\s*(.*)$"m
const _ANOMALOUS_RE = r"anomalous with tr Q_anom\s*=\s*([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)"
const _SUMMARY_ROW_RE = r"^\s*(\d+)\s*\(([^)]*)\)_(\w+)\s+U\(1\)\s*:\s*\(([^)]*)\)\s*$"
const _LABELED_SUMMARY_ROW_RE =
    r"^\s*(\d+)\s*\(([^)]*)\)_(\w+)\s+U\(1\)\s*:\s*\(([^)]*)\)\s+(.+?)\s*$"
const _TWIST_ROW_RE = r"^\s*v_(\d+)\s*=\s*\(([^)]*)\)\s*$"
const _VECTOR16_ROW_RE = r"^\s*(\w+)\s*=\s*\(([^)]*)\),\s*\(([^)]*)\)\s*$"
const _WL_IDENTIFICATIONS_RE = r"^\s*(W_\d+)\s*=\s*(W_\d+)\s*$"
const _WL_ORDERS_RE = r"Allowed orders of the Wilson lines:\s*(.*?)\s*$"

function _parse_gauge_group_factors(factors_str::AbstractString)
    nonabelian = String[]
    n_u1 = 0
    for block in split(factors_str, " and ")
        block = strip(replace(block, '[' => "", ']' => ""))
        if startswith(block, "U(1)")
            m = match(r"^U\(1\)\^(\d+)$", block)
            if m !== nothing
                n_u1 += parse(Int, m.captures[1])
            else
                n_u1 += length(collect(eachmatch(r"U\(1\)(_\d+)?", block)))
            end
        else
            append!(nonabelian, strip.(split(block, " x ")))
        end
    end
    return nonabelian, n_u1
end

"""
    parse_gauge_group(output::AbstractString) -> GaugeGroup

Parse the `Gauge group in vev-configuration "..."` header line, as printed by
both `print summary` (in `cd spectrum`) and `print gauge group` (in `cd
"gauge group"`).
"""
function parse_gauge_group(output::AbstractString)
    m = match(_GAUGE_GROUP_HEADER_RE, output)
    m === nothing && error("no gauge group header found in output")
    config_label = String(m.captures[1])
    nonabelian, n_u1 = _parse_gauge_group_factors(m.captures[2])
    return GaugeGroup(config_label, nonabelian, n_u1)
end

"""
    parse_spectrum(output::AbstractString) -> Spectrum

Parse the output of `print summary` (in `cd spectrum`) into a [`Spectrum`](@ref).
"""
function parse_spectrum(output::AbstractString)
    gauge_group = parse_gauge_group(output)

    anomalous_tr_q = nothing
    m = match(_ANOMALOUS_RE, output)
    m !== nothing && (anomalous_tr_q = parse(Float64, m.captures[1]))

    fields = SpectrumField[]
    for line in split(output, '\n')
        m = match(_SUMMARY_ROW_RE, line)
        m === nothing && continue
        multiplicity = parse(Int, m.captures[1])
        rep = [parse(Int, strip(tok)) for tok in split(m.captures[2], ',')]
        statistic = Symbol(m.captures[3])
        charges = parse_rational_vector(m.captures[4])
        push!(fields, SpectrumField(multiplicity, rep, statistic, charges))
    end
    return Spectrum(gauge_group, anomalous_tr_q, fields)
end

const _FIELD_DETAIL_START_RE =
    r"(?m)^\s{4}(?:(CPT partner|modulus|gauge boson|graviton):\s+)?(\S+)(?:\s+\(\s*(\S+)\s*\))?\s*\n\s*sector \("
const _FIELD_NUMBER_RE = r"(?m)^\s*field no\.\s*:\s*(\d+)\s*$"
const _DETAIL_SECTOR_RE = r"(?m)^\s*sector \([^)]*\)\s*:\s*\(([^)]*)\)\s*$"
const _DETAIL_TRANSLATION_RE = r"(?m)^\s*fixed point n_a\s*:\s*\(([^)]*)\)\s*$"
const _DETAIL_REP_RE =
    r"(?m)^\s*(?:rep\. in config|representation)\s*:\s*\(([^)]*)\)_(\w+)\s+U\(1\)\s*:\s*\(([^)]*)\)"
const _DETAIL_SPACE_GROUP_CHARGES_RE = r"(?m)^\s*space group charges\s*:\s*\(([^)]*)\)\s*$"
const _DETAIL_R_CHARGES_RE = r"(?m)^\s*R charges\s*:\s*\(([^)]*)\)\s*$"
const _DETAIL_RIGHT_MOVER_RE = r"(?m)^\s*right-moving q_sh\s*:\s*\(([^)]*)\)\s*$"

_parse_int_vector(s::AbstractString) = [parse(Int, strip(tok)) for tok in split(s, ',')]

function _multiplet_type(prefix::Union{Nothing,SubString{String}}, statistic::Symbol)
    prefix === nothing || return Symbol(replace(String(prefix), ' ' => '_'))
    return get(Dict(:l => :left_chiral, :s => :scalar, :f => :left_fermi), statistic, statistic)
end

function _required_match(re::Regex, block::AbstractString, description::AbstractString)
    m = match(re, block)
    m === nothing && error("malformed detailed field output: missing $description\n$block")
    return m
end

function _parse_field_details(output::AbstractString)
    starts = collect(eachmatch(_FIELD_DETAIL_START_RE, output))
    isempty(starts) && error("no detailed fields found in output")
    fields = DetailedField[]
    for (i, start) in enumerate(starts)
        stop = i == length(starts) ? lastindex(output) : starts[i+1].offset - 1
        block = SubString(output, start.offset, stop)
        number = parse(Int, _required_match(_FIELD_NUMBER_RE, block, "field number").captures[1])
        sector = Sector(_parse_int_vector(_required_match(_DETAIL_SECTOR_RE, block, "sector").captures[1]))
        translation = parse_rational_vector(
            _required_match(_DETAIL_TRANSLATION_RE, block, "constructing-element translation").captures[1],
        )
        rep_match = _required_match(_DETAIL_REP_RE, block, "representation")
        rep = _parse_int_vector(rep_match.captures[1])
        statistic = Symbol(rep_match.captures[2])
        charges = parse_rational_vector(rep_match.captures[3])
        sg_match = match(_DETAIL_SPACE_GROUP_CHARGES_RE, block)
        r_match = match(_DETAIL_R_CHARGES_RE, block)
        q_match = match(_DETAIL_RIGHT_MOVER_RE, block)
        q_match === nothing && error("malformed detailed field output: missing right-moving momentum\n$block")
        push!(fields, DetailedField(
            FieldID(number), String(start.captures[2]), rep, statistic, charges,
            _multiplet_type(start.captures[1], statistic), sector, translation, nothing,
            sg_match === nothing ? Rational{Int}[] : parse_rational_vector(sg_match.captures[1]),
            r_match === nothing ? Rational{Int}[] : parse_rational_vector(r_match.captures[1]),
            parse_rational_vector(q_match.captures[1]),
        ))
    end
    length(unique(f.id for f in fields)) == length(fields) || error("duplicate upstream field number in detailed output")
    length(unique(f.label for f in fields)) == length(fields) || error("duplicate field label in detailed output")
    return fields
end

const _FIXED_BLOCK_START_RE = r"(?m)^\s*sector:\s*\([^)]*\)\s*=\s*\(([^)]*)\)\s*$"
const _FIXED_LABEL_RE = r"(?m)^\s*fixed point:\s*(\S+)\s*$"
const _FIXED_TRANSLATION_RE = r"(?m)^\s*n_a\s*=\s*\(([^)]*)\)\s*$"
const _FIXED_LOCAL_SHIFT_RE = r"(?m)^\s*V_loc\s*=\s*\(([^)]*)\),\s*\(([^)]*)\)\s*$"

function _expand_field_labels(text::AbstractString)
    labels = String[]
    tokens = split(strip(text))
    i = 1
    while i <= length(tokens)
        if i + 2 <= length(tokens) && tokens[i+1] == "-"
            first_match = match(r"^(.*_)(\d+)$", tokens[i])
            last_match = match(r"^(.*_)(\d+)$", tokens[i+2])
            if first_match !== nothing && last_match !== nothing && first_match.captures[1] == last_match.captures[1]
                append!(labels, ["$(first_match.captures[1])$n" for n in parse(Int, first_match.captures[2]):parse(Int, last_match.captures[2])])
                i += 3
                continue
            end
        end
        push!(labels, String(tokens[i]))
        i += 1
    end
    return labels
end

function _parse_localizations(output::AbstractString)
    starts = collect(eachmatch(_FIXED_BLOCK_START_RE, output))
    isempty(starts) && error("no fixed-point localization found in output")
    result = Dict{String,FieldLocalization}()
    for (i, start) in enumerate(starts)
        stop = i == length(starts) ? lastindex(output) : starts[i+1].offset - 1
        block = SubString(output, start.offset, stop)
        label_match = match(_FIXED_LABEL_RE, block)
        translation_match = match(_FIXED_TRANSLATION_RE, block)
        shift_match = match(_FIXED_LOCAL_SHIFT_RE, block)
        # A command transcript can contain non-table prose after the last block;
        # only complete fixed-point blocks carry field localization data.
        (label_match === nothing || translation_match === nothing || shift_match === nothing) && continue
        localization = FieldLocalization(
            String(label_match.captures[1]), parse_rational_vector(translation_match.captures[1]),
            vcat(parse_rational_vector(shift_match.captures[1]), parse_rational_vector(shift_match.captures[2])),
        )
        for line in split(block, '\n')
            row = match(_LABELED_SUMMARY_ROW_RE, line)
            row === nothing && continue
            for field_label in _expand_field_labels(row.captures[5])
                if haskey(result, field_label) && result[field_label] != localization
                    error("field label $field_label has conflicting fixed-point localizations")
                end
                result[field_label] = localization
            end
        end
    end
    return result
end

"""
    parse_detailed_spectrum(summary_output, fields_output, localization_output) -> DetailedSpectrum

Parse `print summary`, `print(*) with internal information`, and `print summary
of fixed points with labels` output into grouped and individual spectrum views.
The parser verifies field counts, quantum numbers, constructing elements, and
localization joins instead of returning a partial result.
"""
function parse_detailed_spectrum(
    summary_output::AbstractString,
    fields_output::AbstractString,
    localization_output::AbstractString,
)
    summary = parse_spectrum(summary_output)
    fields = _parse_field_details(fields_output)
    localizations = _parse_localizations(localization_output)
    localized_fields = DetailedField[]
    for field in fields
        localization = get(localizations, field.label, nothing)
        localization === nothing && error("no fixed-point localization found for field label $(field.label)")
        localization.translation == field.constructing_translation || error(
            "constructing-element translation disagrees for field label $(field.label)",
        )
        push!(localized_fields, DetailedField(
            field.id, field.label, field.rep, field.statistic, field.charges, field.multiplet_type,
            field.sector, field.constructing_translation, localization, field.space_group_charges,
            field.r_charges, field.right_moving_momentum,
        ))
    end

    grouped = Dict{Tuple{Tuple{Vararg{Int}},Symbol,Tuple{Vararg{Rational{Int}}}},Int}()
    for field in localized_fields
        key = (Tuple(field.rep), field.statistic, Tuple(field.charges))
        grouped[key] = get(grouped, key, 0) + 1
    end
    for row in summary.fields
        key = (Tuple(row.rep), row.statistic, Tuple(row.charges))
        get(grouped, key, 0) == row.multiplicity || error(
            "detailed fields do not reproduce summary multiplicity $(row.multiplicity) for representation $(row.rep)_$(row.statistic)",
        )
        delete!(grouped, key)
    end
    isempty(grouped) || error("detailed output contains quantum-number groups absent from summary")
    return DetailedSpectrum(summary, localized_fields)
end

"""
    find_fields(spectrum::DetailedSpectrum; representation, charge, charges,
                sector, statistic, label, multiplet_type)

Return individual fields satisfying all supplied predicates. `charge = i => q`
matches the `i`th U(1) charge; `charges` and `representation` match complete
vectors. `sector` accepts a [`Sector`](@ref) or a coordinate vector/tuple.
"""
function find_fields(
    spectrum::DetailedSpectrum;
    representation = nothing,
    charge = nothing,
    charges = nothing,
    sector = nothing,
    statistic = nothing,
    label = nothing,
    multiplet_type = nothing,
)
    sector_value = sector === nothing || sector isa Sector ? sector : Sector(collect(Int, sector))
    return filter(spectrum.fields) do field
        (representation === nothing || field.rep == collect(Int, representation)) &&
        (charges === nothing || field.charges == Rational{Int}.(charges)) &&
        (sector_value === nothing || field.sector == sector_value) &&
        (statistic === nothing || field.statistic == statistic) &&
        (label === nothing || field.label == label) &&
        (multiplet_type === nothing || field.multiplet_type == multiplet_type) &&
        (charge === nothing || begin
            i, value = charge
            1 <= i <= length(field.charges) && field.charges[i] == Rational{Int}(value)
        end)
    end
end

"""
    parse_twist(output::AbstractString) -> Twist

Parse the output of `print twist` (in `cd model`) into a [`Twist`](@ref).
"""
function parse_twist(output::AbstractString)
    vectors = Vector{Rational{Int}}[]
    for line in split(output, '\n')
        m = match(_TWIST_ROW_RE, line)
        m === nothing && continue
        push!(vectors, parse_rational_vector(m.captures[2]))
    end
    isempty(vectors) && error("no twist vector found in output")
    return Twist(vectors)
end

"""
    parse_shift_vectors(output::AbstractString) -> Vector{ShiftVector}

Parse the output of `print shift` (in `cd model`) into [`ShiftVector`](@ref)s.
Each `V_i` is printed as two comma-separated 8D groups (the two \$E_8\$ halves
of the 16D lattice, or two 8D halves of \$\\mathrm{SO}(32)\$); they are
concatenated into a single 16D vector.
"""
function parse_shift_vectors(output::AbstractString)
    shifts = ShiftVector[]
    for line in split(output, '\n')
        m = match(_VECTOR16_ROW_RE, line)
        m === nothing && continue
        startswith(m.captures[1], "V_") || continue
        vector = vcat(parse_rational_vector(m.captures[2]), parse_rational_vector(m.captures[3]))
        push!(shifts, ShiftVector(String(m.captures[1]), vector))
    end
    isempty(shifts) && error("no shift vector found in output")
    return shifts
end

"""
    parse_wilson_lines(output::AbstractString) -> WilsonLines

Parse the output of `print Wilson lines` (in `cd model`) into [`WilsonLines`](@ref).
"""
function parse_wilson_lines(output::AbstractString)
    identifications = Tuple{String,String}[]
    orders = Int[]
    lines_out = WilsonLine[]

    for line in split(output, '\n')
        m = match(_WL_ORDERS_RE, line)
        if m !== nothing
            orders = [parse(Int, tok) for tok in split(strip(m.captures[1]))]
            continue
        end
        for tok in split(line, ", ")
            m2 = match(_WL_IDENTIFICATIONS_RE, tok)
            m2 !== nothing && push!(identifications, (String(m2.captures[1]), String(m2.captures[2])))
        end
        m3 = match(_VECTOR16_ROW_RE, line)
        if m3 !== nothing && startswith(m3.captures[1], "W_")
            vector = vcat(parse_rational_vector(m3.captures[2]), parse_rational_vector(m3.captures[3]))
            push!(lines_out, WilsonLine(String(m3.captures[1]), vector))
        end
    end
    isempty(lines_out) && error("no Wilson line found in output")
    return WilsonLines(lines_out, identifications, orders)
end
