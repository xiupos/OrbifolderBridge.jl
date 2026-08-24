const _CONFIG_ROW_RE =
    r"^\s*(->)?\s*\"([^\"]+)\"\s*\|\s*(\d+)\s*/\s*(\d+)\s*\|?\s*(.*?)\s*$"
const _CONFIG_CONTINUATION_RE = r"^\s*\|\s*\|\s*(.*?)\s*$"

_parse_vev_labels(text::AbstractString) =
    strip.(filter(!isempty, split(strip(text))), Ref(['<', '>']))

"""
    parse_vev_configurations(output) -> Vector{VEVConfigurationSummary}

Parse the `print configs` table emitted by either supported backend.
"""
function parse_vev_configurations(output::AbstractString)
    configs = VEVConfigurationSummary[]
    for line in split(output, '\n')
        m = match(_CONFIG_ROW_RE, line)
        if m !== nothing
            push!(configs, VEVConfigurationSummary(
                VEVConfigurationRef(m.captures[2]),
                m.captures[1] !== nothing,
                parse(Int, m.captures[3]),
                parse(Int, m.captures[4]),
                String.(_parse_vev_labels(m.captures[5])),
            ))
            continue
        end
        continuation = match(_CONFIG_CONTINUATION_RE, line)
        if continuation !== nothing && !isempty(configs)
            append!(configs[end].fields_with_vev, _parse_vev_labels(continuation.captures[1]))
        end
    end
    isempty(configs) && error("no VEV configuration rows found in output")
    count(c -> c.selected, configs) == 1 ||
        error("VEV configuration table must contain exactly one selected row")
    return configs
end

function _sector_factor_tokens(text::AbstractString)
    nonabelian = Tuple{String,Bool}[]
    u1 = Bool[]
    for block in split(text, " and ")
        if occursin(r"U\s*\(1\)", block)
            for m in eachmatch(r"(\[?)U\s*\(1\)(?:_[^\] x]+)?(\]?)", block)
                push!(u1, m.captures[1] != "[")
            end
        else
            for token in split(block, " x ")
                value = strip(token)
                hidden = startswith(value, '[') && endswith(value, ']')
                push!(nonabelian, (strip(value, ['[', ']']), hidden))
            end
        end
    end
    return nonabelian, u1
end

"""
    parse_gauge_sector(output) -> GaugeSector

Parse `print gauge group` including the bracket notation that identifies
hidden non-abelian and U(1) factors.
"""
function parse_gauge_sector(output::AbstractString)
    m = match(_GAUGE_GROUP_HEADER_RE, output)
    m === nothing && error("no gauge group header found in output")
    nonabelian, u1 = _sector_factor_tokens(m.captures[2])
    group = GaugeGroup(String(m.captures[1]), first.(nonabelian), length(u1))
    observable_nonabelian = findall(x -> !x[2], nonabelian)
    hidden_nonabelian = findall(x -> x[2], nonabelian)
    observable_u1 = findall(identity, u1)
    hidden_u1 = findall(!, u1)
    return GaugeSector(
        group,
        observable_nonabelian,
        hidden_nonabelian,
        observable_u1,
        hidden_u1,
    )
end

_use_configuration_command(config::VEVConfigurationRef) = "use config($(config.label))"

function _configuration_commands(config, commands::Vector{String})
    config === nothing && return commands
    return vcat(["cd vev-config", _use_configuration_command(config), "cd .."], commands)
end

_validate_configuration_selection(::AbstractString, ::Nothing) = nothing

function _validate_configuration_selection(output::AbstractString, config::VEVConfigurationRef)
    expected = "Now using vev-configuration \"$(config.label)\"."
    already_selected = "Vev-configuration \"$(config.label)\" is already in use."
    (occursin(expected, output) || occursin(already_selected, output)) && return nothing
    throw(VEVConfigurationError(
        config,
        "upstream did not select VEV configuration \"$(config.label)\"",
        String(output),
    ))
end

const _DETAIL_VEV_RE = r"(?m)^\s*vev\s*:\s*([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)\s*$"

"""
    parse_field_vevs(output) -> Vector{FieldVEV}

Parse nonzero numerical VEVs from SUSY `with internal information` output.
Fields without a printed `vev` line are omitted.
"""
function parse_field_vevs(output::AbstractString)
    starts = collect(eachmatch(_FIELD_DETAIL_START_RE, output))
    isempty(starts) && error("no detailed fields found in output")
    assignments = FieldVEV[]
    for (i, start) in enumerate(starts)
        stop = i == length(starts) ? lastindex(output) : starts[i+1].offset - 1
        block = SubString(output, start.offset, stop)
        vev_match = match(_DETAIL_VEV_RE, block)
        vev_match === nothing && continue
        number = parse(Int, _required_match(_FIELD_NUMBER_RE, block, "field number").captures[1])
        value = parse(Float64, vev_match.captures[1])
        iszero(value) && continue
        push!(assignments, FieldVEV(
            FieldID(number),
            String(start.captures[2]),
            value,
        ))
    end
    return assignments
end

function _detailed_commands()
    return [
        "cd spectrum",
        "print summary",
        "print(*) with internal information",
        "print summary of fixed points with labels",
    ]
end

function _resolve_configuration_spec(
    model::OrbifolderModel,
    spec::VEVConfigurationSpec;
    timeout::Real,
)
    commands = vcat(
        ["cd vev-config", "print configs", _use_configuration_command(spec.base), "cd .."],
        _detailed_commands(),
    )
    output = _run_model_script(model, commands; timeout = timeout)
    _validate_configuration_selection(output, spec.base)
    pairs = split_transcript(output)
    configs = parse_vev_configurations(output_for(pairs, "print configs"))
    any(c -> c.configuration == spec.configuration, configs) && throw(ArgumentError(
        "VEV configuration \"$(spec.configuration.label)\" already exists when the model is loaded",
    ))
    detailed_output = output_for(pairs, "print(*) with internal information")
    detailed = parse_detailed_spectrum(
        output_for(pairs, "print summary"),
        detailed_output,
        output_for(pairs, "print summary of fixed points with labels"),
    )
    fields = Dict(field.id => field for field in detailed.fields)
    labels = Dict{FieldID,String}()
    for assignment in spec.assignments
        field = get(fields, assignment.field, nothing)
        field === nothing && throw(ArgumentError(
            "field number $(assignment.field.number) does not exist in base configuration $(spec.base.label)",
        ))
        all(==(1), abs.(field.rep)) || throw(ArgumentError(
            "field $(field.label) is not a non-abelian singlet; upstream does not expose VEV component selection",
        ))
        labels[field.id] = field.label
    end
    return (; detailed, labels, transcript = output)
end

function _validate_observable_indices(spec::VEVConfigurationSpec, detailed::DetailedSpectrum)
    n_nonabelian = length(detailed.summary.gauge_group.nonabelian)
    n_u1 = detailed.summary.gauge_group.n_u1
    for (description, indices, count) in (
        ("observable_nonabelian", spec.observable_nonabelian, n_nonabelian),
        ("observable_u1", spec.observable_u1, n_u1),
    )
        indices === nothing && continue
        all(<=(count), indices) || throw(ArgumentError(
            "$description contains an index greater than the available factor count $count",
        ))
    end
    return nothing
end

function _observable_sector_command(spec::VEVConfigurationSpec)
    parts = String[]
    if spec.observable_nonabelian !== nothing
        push!(parts, isempty(spec.observable_nonabelian) ? "no gauge groups" :
              "gauge group($(join(spec.observable_nonabelian, ',')))")
    end
    if spec.observable_u1 !== nothing
        push!(parts, isempty(spec.observable_u1) ? "no U1s" :
              "U1s($(join(spec.observable_u1, ',')))")
    end
    return isempty(parts) ? nothing : "select observable sector: $(join(parts, ' '))"
end

function _configuration_spec_commands(
    model::OrbifolderModel,
    spec::VEVConfigurationSpec,
    resolution,
)
    !isempty(spec.assignments) && model.mode !== :susy && throw(ArgumentError(
        "fixed VEV assignments are supported only by the SUSY backend",
    ))
    spec.recompute_unbroken_group && model.mode !== :susy && throw(ArgumentError(
        "unbroken gauge-group recomputation is supported only by the SUSY backend",
    ))
    _validate_observable_indices(spec, resolution.detailed)
    commands = [
        "cd vev-config",
        "create config($(spec.configuration.label)) from($(spec.base.label))",
    ]
    observable = _observable_sector_command(spec)
    observable === nothing || push!(commands, observable)
    for assignment in spec.assignments
        label = resolution.labels[assignment.field]
        push!(commands, "vev($label)=$(repr(assignment.value))")
    end
    spec.recompute_unbroken_group && push!(commands, "find unbroken gauge group")
    return commands
end

function _validate_configuration_creation(output::AbstractString, spec::VEVConfigurationSpec)
    expected = "Vev-configuration \"$(spec.configuration.label)\" created from \"$(spec.base.label)\"."
    occursin(expected, output) && return nothing
    throw(VEVConfigurationError(
        spec.configuration,
        "upstream did not create the requested VEV configuration from $(spec.base.label)",
        String(output),
    ))
end

function _run_configuration_spec(
    model::OrbifolderModel,
    spec::VEVConfigurationSpec,
    tail::Vector{String};
    timeout::Real = 120,
)
    resolution = _resolve_configuration_spec(model, spec; timeout = timeout)
    prefix = _configuration_spec_commands(model, spec, resolution)
    output = _run_model_script(model, vcat(prefix, tail); timeout = timeout)
    _validate_configuration_creation(output, spec)
    return (; output, resolution)
end

"""
    materialize_vev_configuration(model, specification; timeout = 120)

Replay a declarative configuration in an isolated upstream process and return
its VEVs, observable/hidden gauge sector, grouped spectrum, and detailed
spectrum. Fixed VEV assignment and unbroken-group recomputation are available
only with the SUSY backend; both backends support configuration derivation and
observable-sector selection.
"""
function materialize_vev_configuration(
    model::OrbifolderModel,
    spec::VEVConfigurationSpec;
    timeout::Real = 120,
)
    info = backend_info(model.mode; timeout = min(timeout, 30))
    tail = [
        "print configs",
        "print gauge group",
        "cd ..",
        _detailed_commands()...,
    ]
    run = _run_configuration_spec(model, spec, tail; timeout = timeout)
    pairs = split_transcript(run.output)
    configs = parse_vev_configurations(output_for(pairs, "print configs"))
    config = only(filter(c -> c.configuration == spec.configuration && c.selected, configs))
    gauge_sector = parse_gauge_sector(output_for(pairs, "print gauge group"))
    detailed_output = output_for(pairs, "print(*) with internal information")
    summary_output = output_for(pairs, "print summary")
    detailed = isempty(gauge_sector.hidden_nonabelian) ? parse_detailed_spectrum(
        summary_output,
        detailed_output,
        output_for(pairs, "print summary of fixed points with labels"),
    ) : nothing
    spectrum = parse_spectrum(summary_output)
    assignments = parse_field_vevs(detailed_output)
    requested_ids = Set(a.field for a in spec.assignments if !iszero(a.value))
    read_ids = Set(getfield.(assignments, :field))
    requested_ids == read_ids || throw(VEVConfigurationError(
        spec.configuration,
        "upstream VEV readback does not match the requested fields",
        run.output,
    ))
    return VEVConfigurationResult(
        spec,
        config,
        assignments,
        gauge_sector,
        spectrum,
        detailed,
        info,
        run.resolution.transcript,
        run.output,
    )
end

compute_gauge_group(model::OrbifolderModel, spec::VEVConfigurationSpec; kwargs...) =
    materialize_vev_configuration(model, spec; kwargs...).gauge_sector.gauge_group

compute_gauge_sector(model::OrbifolderModel, spec::VEVConfigurationSpec; kwargs...) =
    materialize_vev_configuration(model, spec; kwargs...).gauge_sector

compute_spectrum(model::OrbifolderModel, spec::VEVConfigurationSpec; kwargs...) =
    materialize_vev_configuration(model, spec; kwargs...).spectrum

function compute_detailed_spectrum(
    model::OrbifolderModel,
    spec::VEVConfigurationSpec;
    kwargs...,
)
    detailed = materialize_vev_configuration(model, spec; kwargs...).detailed_spectrum
    detailed === nothing && throw(ArgumentError(
        "detailed spectrum multiplicities are ambiguous when non-abelian factors are hidden",
    ))
    return detailed
end

"""
    list_vev_configurations(model; timeout = 120)

List the VEV configurations created by upstream when `model` is loaded.
Exactly one returned entry has `selected == true`.
"""
function list_vev_configurations(model::OrbifolderModel; timeout::Real = 120)
    out = _run_model_script(model, ["cd vev-config", "print configs"]; timeout = timeout)
    return parse_vev_configurations(output_for(split_transcript(out), "print configs"))
end

"""
    compute_gauge_sector(model, config; timeout = 120) -> GaugeSector

Select `config` explicitly and return its observable/hidden gauge-sector
partition as reported by upstream.
"""
function compute_gauge_sector(
    model::OrbifolderModel,
    config::VEVConfigurationRef;
    timeout::Real = 120,
)
    commands = ["cd vev-config", _use_configuration_command(config), "print gauge group"]
    out = _run_model_script(model, commands; timeout = timeout)
    _validate_configuration_selection(out, config)
    return parse_gauge_sector(output_for(split_transcript(out), "print gauge group"))
end
