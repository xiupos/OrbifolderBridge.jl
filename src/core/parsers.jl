const _GAUGE_GROUP_HEADER_RE =
    r"Gauge group in vev-configuration \"([^\"]*)\":\s*(.*)$"m
const _ANOMALOUS_RE = r"anomalous with tr Q_anom\s*=\s*([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)"
const _SUMMARY_ROW_RE = r"^\s*(\d+)\s*\(([^)]*)\)_(\w+)\s+U\(1\)\s*:\s*\(([^)]*)\)\s*$"
const _TWIST_ROW_RE = r"^\s*v_(\d+)\s*=\s*\(([^)]*)\)\s*$"
const _VECTOR16_ROW_RE = r"^\s*(\w+)\s*=\s*\(([^)]*)\),\s*\(([^)]*)\)\s*$"
const _WL_IDENTIFICATIONS_RE = r"^\s*(W_\d+)\s*=\s*(W_\d+)\s*$"
const _WL_ORDERS_RE = r"Allowed orders of the Wilson lines:\s*(.*?)\s*$"

function _parse_gauge_group_factors(factors_str::AbstractString)
    nonabelian = String[]
    n_u1 = 0
    for block in split(factors_str, " and ")
        block = strip(block)
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
