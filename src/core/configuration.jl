const _CONFIG_ROW_RE =
    r"^\s*(->)?\s*\"([^\"]+)\"\s*\|\s*(\d+)\s*/\s*(\d+)\s*\|?\s*(.*?)\s*$"

"""
    parse_vev_configurations(output) -> Vector{VEVConfigurationSummary}

Parse the `print configs` table emitted by either supported backend.
"""
function parse_vev_configurations(output::AbstractString)
    configs = VEVConfigurationSummary[]
    for line in split(output, '\n')
        m = match(_CONFIG_ROW_RE, line)
        m === nothing && continue
        fields = filter(!isempty, split(strip(m.captures[5])))
        push!(configs, VEVConfigurationSummary(
            VEVConfigurationRef(m.captures[2]),
            m.captures[1] !== nothing,
            parse(Int, m.captures[3]),
            parse(Int, m.captures[4]),
            String.(fields),
        ))
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
    occursin(expected, output) && return nothing
    throw(VEVConfigurationError(
        config,
        "upstream did not select VEV configuration \"$(config.label)\"",
        String(output),
    ))
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
