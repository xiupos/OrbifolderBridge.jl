"""
    GeometryParseError <: Exception

Thrown when geometry output does not match the supported upstream grammar.
The complete raw output is retained in `output` for diagnosis.
"""
struct GeometryParseError <: Exception
    message::String
    output::String
end

Base.showerror(io::IO, e::GeometryParseError) = print(io, "GeometryParseError: ", e.message)

_geometry_error(message, output) = throw(GeometryParseError(message, String(output)))

function _point_group_orders(text::AbstractString, output::AbstractString)
    orders = parse.(Int, getindex.(collect(eachmatch(r"Z_(\d+)", text)), 1))
    isempty(orders) && _geometry_error("point-group order is missing", output)
    return orders
end

"""
    parse_available_space_groups(output; backend) -> Vector{SpaceGroupInfo}

Parse `print available space groups` output. `backend` is `:susy` or
`:nonsusy`; retaining it prevents entries from the two different Geometry
grammars from being mixed accidentally.
"""
function parse_available_space_groups(output::AbstractString; backend::Symbol)
    _check_mode(backend)
    header = match(r"available\s+(.+?)\s+space groups:\s*(?:none)?\s*$"m, output)
    header === nothing && _geometry_error("available-space-groups header is missing", output)
    orders = _point_group_orders(header.captures[1], output)
    entries = SpaceGroupInfo[]
    row_re = r"^\s*(\d+)\s*\|\s*([^|]+?)\s*\|\s*([^|]*?)\s*\|\s*\"([^\"]+)\"\s*$"m
    for row in eachmatch(row_re, output)
        push!(entries, SpaceGroupInfo(
            backend, parse(Int, row.captures[1]), orders,
            strip(row.captures[2]), strip(row.captures[3]), String(row.captures[4]),
        ))
    end
    isempty(entries) && occursin(r"space groups:\s*none", output) && return entries
    isempty(entries) && _geometry_error("no space-group table rows found", output)
    getfield.(entries, :index) == collect(1:length(entries)) ||
        _geometry_error("space-group table indices are not contiguous", output)
    length(unique(getfield.(entries, :geometry_file))) == length(entries) ||
        _geometry_error("space-group table contains duplicate Geometry files", output)
    return entries
end

function _parse_space_group_element(m::RegexMatch, output::AbstractString)
    sector = try
        Sector(parse.(Int, strip.(split(m.captures[1], ','))))
    catch
        _geometry_error("invalid sector in space-group generator", output)
    end
    translation = try
        parse_rational_vector(m.captures[2])
    catch
        _geometry_error("invalid translation in space-group generator", output)
    end
    length(translation) == 6 || _geometry_error("space-group translation must have six entries", output)
    return SpaceGroupElement(sector, translation)
end

"""
    parse_space_group_metadata(point_group_output, space_group_output;
                               backend, geometry_file) -> SpaceGroupMetadata

Parse the results of `print point group` and `print space group`, including
the compactification root-lattice label and upstream space-group generators.
"""
function parse_space_group_metadata(
    point_group_output::AbstractString,
    space_group_output::AbstractString;
    backend::Symbol,
    geometry_file::AbstractString,
)
    _check_mode(backend)
    point = match(r"Point group is\s+(.+?)\.\s*$"m, point_group_output)
    point === nothing && _geometry_error("point-group description is missing", point_group_output)
    orders = _point_group_orders(point.captures[1], point_group_output)
    expected_sector_length = backend === :susy ? 2 : 3
    header = match(
        r"Space group based on\s+(.+?)\s+point group and root-lattice of\s+([^\.]+)\."m,
        space_group_output,
    )
    header === nothing && _geometry_error("space-group description is missing", space_group_output)
    _point_group_orders(header.captures[1], space_group_output) == orders ||
        _geometry_error("point-group and space-group outputs disagree", space_group_output)
    generators = SpaceGroupElement[]
    for m in eachmatch(r"\(([^()]*)\)\s*\(([^()]*)\)", space_group_output)
        element = _parse_space_group_element(m, space_group_output)
        length(element.sector.coordinates) == expected_sector_length || _geometry_error(
            "space-group generator has the wrong sector arity for :$backend",
            space_group_output,
        )
        push!(generators, element)
    end
    isempty(generators) && _geometry_error("space-group generators are missing", space_group_output)
    additional = match(r"\s-\s(.+)$", strip(point.captures[1]))
    return SpaceGroupMetadata(
        backend, orders, strip(header.captures[2]),
        additional === nothing ? "" : strip(additional.captures[1]),
        String(geometry_file), generators,
    )
end

"""
    available_space_groups(model; timeout = 120) -> Vector{SpaceGroupInfo}

Ask upstream to enumerate Geometry files compatible with `model`'s point
group. The result reflects the configured backend's staged `Geometry/`
directory rather than a filename convention implemented by the bridge.
"""
function available_space_groups(model::OrbifolderModel; timeout::Real = 120)
    output = _run_model_script(model, ["cd model", "print available space groups"]; timeout = timeout)
    return parse_available_space_groups(
        output_for(split_transcript(output), "print available space groups");
        backend = model.mode,
    )
end

"""
    space_group_metadata(model; timeout = 120) -> SpaceGroupMetadata

Return the point group, compactification lattice label, and generators
reported by upstream for the selected Geometry file.
"""
function space_group_metadata(model::OrbifolderModel; timeout::Real = 120)
    output = _run_model_script(
        model, ["cd model", "print point group", "print space group"];
        timeout = timeout,
    )
    pairs = split_transcript(output)
    return parse_space_group_metadata(
        output_for(pairs, "print point group"), output_for(pairs, "print space group");
        backend = model.mode, geometry_file = model.space_group_file,
    )
end

"""
    localizations(spectrum::DetailedSpectrum) -> Vector{Localization}

Group individually identified fields by the complete upstream constructing
element and fixed-point/fixed-brane localization.
"""
function localizations(spectrum::DetailedSpectrum)
    grouped = Dict{Tuple{Tuple{Vararg{Int}},Tuple{Vararg{Rational{Int}}},String,Tuple{Vararg{Rational{Int}}}},Vector{FieldID}}()
    for field in spectrum.fields
        loc = field.localization
        loc === nothing && continue
        key = (
            Tuple(field.sector.coordinates), Tuple(loc.translation), loc.label,
            Tuple(loc.local_shift),
        )
        push!(get!(grouped, key, FieldID[]), field.id)
    end
    result = Localization[]
    for (key, ids) in grouped
        push!(result, Localization(
            key[3], SpaceGroupElement(Sector(collect(key[1])), collect(key[2])),
            collect(key[4]), sort(ids; by = id -> id.number),
        ))
    end
    sort!(result; by = loc -> (
        Tuple(loc.constructing_element.sector.coordinates),
        Tuple(loc.constructing_element.translation), loc.label,
    ))
    return result
end

"""
    compute_localizations(model[, config]; timeout = 120) -> Vector{Localization}

Obtain the detailed spectrum from upstream and return its structured
localizations. `config` has the same explicit VEV-configuration semantics as
[`compute_detailed_spectrum`](@ref).
"""
function compute_localizations(
    model::OrbifolderModel,
    config::Union{Nothing,VEVConfigurationRef} = nothing;
    timeout::Real = 120,
)
    return localizations(compute_detailed_spectrum(model, config; timeout = timeout))
end

"""Return the detailed fields localized at `localization`."""
function fields_at(localization::Localization, spectrum::DetailedSpectrum)
    by_id = Dict(field.id => field for field in spectrum.fields)
    all(id -> haskey(by_id, id), localization.fields) ||
        throw(ArgumentError("localization contains a FieldID absent from the spectrum"))
    return [by_id[id] for id in localization.fields]
end

"""
    local_gauge_data(localization, spectrum) -> LocalGaugeData

Return upstream's exact local shift together with the states at that
localization. No local gauge group is inferred in Julia.
"""
local_gauge_data(localization::Localization, spectrum::DetailedSpectrum) =
    LocalGaugeData(localization, fields_at(localization, spectrum))
