const _COUPLING_VECTOR_TOKEN_RE = r"[-+]?\d+(?:/\d+)?"

function _coupling_parse_error(message::AbstractString, source::AbstractString)
    throw(CouplingParseError(String(message), String(source)))
end

function _parse_coupling_vector(line::AbstractString, source::AbstractString)
    tokens = getfield.(collect(eachmatch(_COUPLING_VECTOR_TOKEN_RE, line)), :match)
    length(tokens) == 16 || _coupling_parse_error(
        "coupling-file gauge vectors must contain 16 entries, got $(length(tokens))",
        source,
    )
    try
        return parse_rational.(tokens)
    catch e
        e isa InterruptException && rethrow()
        _coupling_parse_error("invalid rational in coupling-file gauge data", source)
    end
end

function _validate_coupling_header(
    lines::Vector{SubString{String}},
    model::OrbifolderModel,
    source::AbstractString,
)
    length(lines) >= 9 || _coupling_parse_error(
        "coupling file is missing its lattice, shifts, or Wilson lines",
        source,
    )
    expected_lattice = _LATTICE_KEYWORD[model.lattice]
    strip(lines[1]) == expected_lattice || _coupling_parse_error(
        "coupling file uses lattice $(strip(lines[1])) instead of $expected_lattice",
        source,
    )
    vectors = [_parse_coupling_vector(lines[i], source) for i in 2:9]
    expected = vcat([model.shift1, model.shift2], model.wilson_lines)
    vectors == expected || _coupling_parse_error(
        "coupling-file gauge embedding does not match the supplied model",
        source,
    )
    return nothing
end

"""
    parse_couplings(source, model, fields) -> Vector{CouplingTerm}

Parse the native file emitted by SUSY orbifolder's `save couplings(...)`.
The file's exact lattice embedding is checked against `model`, and every
zero-based upstream field number is checked against `fields`. Empty coupling
sets are represented by an empty vector rather than as an error.
"""
function parse_couplings(
    source::AbstractString,
    model::OrbifolderModel,
    fields::AbstractVector{DetailedField},
)
    raw = String(source)
    lines = split(raw, '\n'; keepempty = false)
    _validate_coupling_header(lines, model, raw)
    known = Set(field.id for field in fields)
    terms = CouplingTerm[]
    for line in lines[10:end]
        tokens = split(strip(line))
        isempty(tokens) && continue
        numbers = try
            parse.(Int, tokens)
        catch e
            e isa InterruptException && rethrow()
            _coupling_parse_error("invalid field number in coupling row: $(strip(line))", raw)
        end
        length(numbers) >= 3 || _coupling_parse_error(
            "saved coupling has order less than 3: $(strip(line))",
            raw,
        )
        ids = FieldID.(numbers)
        unknown = filter(id -> !(id in known), ids)
        isempty(unknown) || _coupling_parse_error(
            "saved coupling refers to unknown field number $(first(unknown).number)",
            raw,
        )
        push!(terms, CouplingTerm(ids))
    end
    length(unique(terms)) == length(terms) ||
        _coupling_parse_error("coupling file contains duplicate terms", raw)
    return terms
end

parse_couplings(
    source::AbstractString,
    model::OrbifolderModel,
    spectrum::DetailedSpectrum,
) = parse_couplings(source, model, spectrum.fields)

function _coupling_labels(
    request::CouplingRequest,
    fields::AbstractVector{DetailedField},
)
    requested = request.allowed_fields === nothing ? request.fields :
                vcat(request.fields, request.allowed_fields)
    return _field_labels(requested, fields)
end

function _field_labels(
    requested::AbstractVector{FieldID},
    fields::AbstractVector{DetailedField},
)
    labels = Dict(field.id => field.label for field in fields)
    for id in requested
        haskey(labels, id) || throw(ArgumentError(
            "field number $(id.number) does not exist in the selected VEV configuration",
        ))
    end
    return labels
end

function _coupling_command(request::CouplingRequest, labels::Dict{FieldID,String})
    command = "create coupling($(join((labels[id] for id in request.fields), ' ')))"
    if request.allowed_fields !== nothing
        command *= " allowed fields($(join((labels[id] for id in request.allowed_fields), ' ')))"
    end
    return command
end

_sanitize_coupling_transcript(text::AbstractString) =
    replace(String(text), r"PID\s+[0-9]+" => "PID <redacted>")

function _reported_coupling_count(output::AbstractString)
    pairs = split_transcript(output)
    wait_outputs = [value for (command, value) in pairs if command == "wait(1)"]
    isempty(wait_outputs) && throw(CouplingExecutionError(
        "upstream transcript does not contain the required wait(1) command",
        String(output),
    ))
    count = 0
    for wait_output in wait_outputs
        matches = collect(eachmatch(r"(?m)^\s*(\d+) couplings created\.\s*$", wait_output))
        isempty(matches) && throw(CouplingExecutionError(
            "upstream did not report a completed coupling calculation",
            String(output),
        ))
        occursin("waiting done.", wait_output) || throw(CouplingExecutionError(
            "upstream coupling child did not report waiting completion",
            String(output),
        ))
        count += sum(parse(Int, m.captures[1]) for m in matches)
    end
    return count
end

function _resolve_coupling_fields(
    model::OrbifolderModel,
    config::VEVConfigurationRef;
    timeout::Real,
)
    prefix = ["cd vev-config", _use_configuration_command(config), "cd .."]
    inspect = ["cd spectrum", "print(*) with internal information", "cd .."]
    inspection = _run_model_script(model, vcat(prefix, inspect); timeout = timeout)
    _validate_configuration_selection(inspection, config)
    field_output = output_for(split_transcript(inspection), "print(*) with internal information")
    return (; prefix, inspection, fields = _parse_field_details(field_output))
end

function _validate_coupling_backend(
    model::OrbifolderModel,
    config::VEVConfigurationRef;
    timeout::Real,
)
    info = backend_info(model.mode; timeout = min(timeout, 30))
    supports(info, :couplings) ||
        throw(ArgumentError("coupling calculations are not supported by :$(model.mode)"))
    startswith(config.label, "StandardConfig") && throw(ArgumentError(
        "upstream disables coupling commands in StandardConfig configurations",
    ))
    return info
end

function _term_involves(term::CouplingTerm, fields::AbstractVector{FieldID})
    required = Dict{FieldID,Int}()
    present = Dict{FieldID,Int}()
    for field in fields
        required[field] = get(required, field, 0) + 1
    end
    for field in term.fields
        present[field] = get(present, field, 0) + 1
    end
    return all(get(present, field, 0) >= count for (field, count) in required)
end

"""
    compute_couplings(model, config, request; timeout = 120) -> CouplingResult

Ask SUSY orbifolder to apply its coupling-selection rules to `request` in the
explicit VEV configuration `config`. The bridge resolves stable field IDs to
the selected configuration's labels, waits for upstream's child calculation,
and parses the native saved result back into stable field references.

```julia
request = CouplingRequest([FieldID(11), FieldID(37), FieldID(39)])
result = compute_couplings(model, VEVConfigurationRef("TestConfig1"), request)
```

The supported non-SUSY backend does not implement coupling calculations.
"""
function compute_couplings(
    model::OrbifolderModel,
    config::VEVConfigurationRef,
    request::CouplingRequest;
    timeout::Real = 120,
)
    info = _validate_coupling_backend(model, config; timeout = timeout)

    output_file = "bridge_couplings.txt"
    # Resolve labels in an isolated run first. A second run performs the
    # calculation so a parser failure cannot leave an upstream child behind.
    resolution = _resolve_coupling_fields(model, config; timeout = timeout)
    labels = _coupling_labels(request, resolution.fields)
    create_command = _coupling_command(request, labels)

    commands = vcat(resolution.prefix, [
        "cd couplings",
        create_command,
        "wait(1)",
        "save couplings($output_file)",
    ])
    result = _run_model_script_artifacts(
        model,
        commands;
        collect_files = [output_file],
        timeout = timeout,
    )
    _validate_configuration_selection(result.output, config)
    haskey(result.files, output_file) || throw(CouplingParseError(
        "upstream did not save the requested coupling file",
        result.output,
    ))
    source = result.files[output_file]
    terms = parse_couplings(source, model, resolution.fields)
    reported_count = _reported_coupling_count(result.output)
    reported_count == length(terms) || throw(CouplingExecutionError(
        "upstream reported $reported_count created couplings but saved $(length(terms)) terms",
        result.output,
    ))
    all(term -> length(term.fields) == length(request.fields), terms) ||
        throw(CouplingParseError("upstream returned a coupling of unexpected order", source))
    return CouplingResult(
        request,
        config,
        terms,
        info,
        _sanitize_coupling_transcript(string(resolution.inspection, '\n', result.output)),
        source,
    )
end

"""
    search_couplings(model, config, requests;
                     involving = FieldID[], max_order) -> CouplingSearchResult

Submit all candidate coupling requests of order at most `max_order` to SUSY
orbifolder in one isolated session, wait for its child calculations, and run
upstream `find(...)` for the stable fields in `involving`. The returned terms
come from the validated native saved file; matching by `involving` is repeated
on those stable IDs so formatted display labels are never the data model.

At least one request must remain after applying `max_order`, which must be at
least three. The supported upstream `save couplings(...) of order(X)` parser
does not reliably read its documented option, so the bridge enforces the
maximum by deciding which explicit requests are submitted for computation.
"""
function search_couplings(
    model::OrbifolderModel,
    config::VEVConfigurationRef,
    requests::AbstractVector{CouplingRequest};
    involving::AbstractVector{FieldID} = FieldID[],
    max_order::Integer,
    timeout::Real = 120,
)
    max_order >= 3 || throw(ArgumentError("max_order must be at least 3"))
    selected = filter(request -> length(request.fields) <= max_order, requests)
    isempty(selected) && throw(ArgumentError(
        "no coupling request remains after applying max_order = $max_order",
    ))
    length(unique(selected)) == length(selected) ||
        throw(ArgumentError("coupling requests must be unique"))
    info = _validate_coupling_backend(model, config; timeout = timeout)
    resolution = _resolve_coupling_fields(model, config; timeout = timeout)

    all_ids = reduce(vcat, (request.fields for request in selected); init = FieldID[])
    for request in selected
        request.allowed_fields === nothing || append!(all_ids, request.allowed_fields)
    end
    append!(all_ids, involving)
    labels = _field_labels(all_ids, resolution.fields)

    output_file = "bridge_coupling_search.txt"
    commands = vcat(resolution.prefix, ["cd couplings"])
    for request in selected
        push!(commands, _coupling_command(request, labels))
        push!(commands, "wait(1)")
    end
    find_fields = isempty(involving) ? "*" : join((labels[id] for id in involving), ' ')
    push!(commands, "find($find_fields)")
    push!(commands, "save couplings($output_file)")
    result = _run_model_script_artifacts(
        model,
        commands;
        collect_files = [output_file],
        timeout = timeout,
    )
    _validate_configuration_selection(result.output, config)
    haskey(result.files, output_file) || throw(CouplingExecutionError(
        "upstream did not save the coupling-search result",
        result.output,
    ))
    source = result.files[output_file]
    all_terms = parse_couplings(source, model, resolution.fields)
    reported_count = _reported_coupling_count(result.output)
    reported_count == length(all_terms) || throw(CouplingExecutionError(
        "upstream reported $reported_count created couplings but saved $(length(all_terms)) terms",
        result.output,
    ))
    terms = filter(term -> _term_involves(term, involving), all_terms)
    return CouplingSearchResult(
        selected,
        collect(involving),
        Int(max_order),
        config,
        terms,
        info,
        _sanitize_coupling_transcript(string(resolution.inspection, '\n', result.output)),
        source,
    )
end

const _EFFECTIVE_TOKEN_RE = r"<[^>]+>|[()+]|[^\s()+]+"

function _multiply_effective_monomials(left, right)
    result = Tuple{Vector{String},Vector{String}}[]
    for (left_fields, left_vevs) in left, (right_fields, right_vevs) in right
        push!(result, (vcat(left_fields, right_fields), vcat(left_vevs, right_vevs)))
    end
    return result
end

function _parse_effective_sum(tokens, position, source)
    result = _parse_effective_product(tokens, position, source)
    while position[] <= length(tokens) && tokens[position[]] == "+"
        position[] += 1
        append!(result, _parse_effective_product(tokens, position, source))
    end
    return result
end

function _parse_effective_atom(tokens, position, source)
    position[] <= length(tokens) ||
        _coupling_parse_error("unexpected end of effective superpotential", source)
    token = tokens[position[]]
    if token == "("
        position[] += 1
        result = _parse_effective_sum(tokens, position, source)
        position[] <= length(tokens) && tokens[position[]] == ")" ||
            _coupling_parse_error("unclosed parenthesis in effective superpotential", source)
        position[] += 1
        return result
    end
    token in ("+", ")") &&
        _coupling_parse_error("unexpected token $token in effective superpotential", source)
    position[] += 1
    if startswith(token, '<') && endswith(token, '>')
        label = token[2:prevind(token, lastindex(token))]
        isempty(label) && _coupling_parse_error("empty VEV field label", source)
        return [(String[], [String(label)])]
    end
    return [([token], String[])]
end

function _parse_effective_product(tokens, position, source)
    result = [(String[], String[])]
    found = false
    while position[] <= length(tokens) && !(tokens[position[]] in ("+", ")"))
        atom = _parse_effective_atom(tokens, position, source)
        result = _multiply_effective_monomials(result, atom)
        found = true
    end
    found || _coupling_parse_error("empty product in effective superpotential", source)
    return result
end

function _parse_effective_expression(tokens::Vector{String}, source::AbstractString)
    position = Ref(1)
    result = _parse_effective_sum(tokens, position, source)
    position[] > length(tokens) ||
        _coupling_parse_error("unexpected trailing effective-superpotential token", source)
    return result
end

_field_multiset(fields::AbstractVector{FieldID}) = sort(getfield.(fields, :number))

"""
    parse_effective_couplings(output, fields, source_terms)
        -> Vector{UpstreamEffectiveCoupling}

Parse SUSY orbifolder's plain `W_eff = ...` output, including implicit
multiplication, sums, parenthesized sums of VEV products, and the `W_eff = 0`
empty result. Every expanded monomial is matched by field multiplicity to one
ordinary source coupling; unknown labels and unmatched terms are errors that
retain the complete output.
"""
function parse_effective_couplings(
    output::AbstractString,
    fields::AbstractVector{DetailedField},
    source_terms::AbstractVector{CouplingTerm},
)
    raw = String(output)
    m = match(r"(?ms)W_eff\s*=\s*(.*?)\s*$", raw)
    m === nothing && _coupling_parse_error("no effective superpotential found", raw)
    expression = strip(m.captures[1])
    expression == "0" && return UpstreamEffectiveCoupling[]
    tokens = String[m.match for m in eachmatch(_EFFECTIVE_TOKEN_RE, expression)]
    isempty(tokens) && _coupling_parse_error("empty effective superpotential", raw)
    monomials = _parse_effective_expression(tokens, raw)
    labels = Dict(field.label => field.id for field in fields)
    available = collect(source_terms)
    result = UpstreamEffectiveCoupling[]
    for (field_labels, vev_labels) in monomials
        all_labels = vcat(field_labels, vev_labels)
        unknown = filter(label -> !haskey(labels, label), all_labels)
        isempty(unknown) || _coupling_parse_error(
            "effective superpotential refers to unknown field label $(first(unknown))",
            raw,
        )
        dynamical = [labels[label] for label in field_labels]
        vevs = [labels[label] for label in vev_labels]
        combined = _field_multiset(vcat(dynamical, vevs))
        index = findfirst(term -> _field_multiset(term.fields) == combined, available)
        index === nothing && _coupling_parse_error(
            "effective monomial does not match a registered source coupling",
            raw,
        )
        source = popat!(available, index)
        push!(result, UpstreamEffectiveCoupling(source, dynamical, vevs))
    end
    isempty(available) || _coupling_parse_error(
        "registered source coupling is absent from the effective superpotential",
        raw,
    )
    return result
end

parse_effective_couplings(
    output::AbstractString,
    spectrum::DetailedSpectrum,
    source_terms::AbstractVector{CouplingTerm},
) = parse_effective_couplings(output, spectrum.fields, source_terms)

"""
    compute_effective_couplings(model, specification, requests; timeout = 120)
        -> EffectiveCouplingResult

Replay a declarative SUSY VEV configuration, register the requested ordinary
couplings through upstream, and parse `print effective superpotential` in the
same isolated process. This is configuration-local by construction; a derived
configuration is never assumed to persist between subprocesses.
"""
function compute_effective_couplings(
    model::OrbifolderModel,
    specification::VEVConfigurationSpec,
    requests::AbstractVector{CouplingRequest};
    timeout::Real = 120,
)
    isempty(requests) && throw(ArgumentError("at least one coupling request is required"))
    length(unique(requests)) == length(requests) ||
        throw(ArgumentError("coupling requests must be unique"))
    info = _validate_coupling_backend(model, specification.configuration; timeout = timeout)
    resolution = _resolve_configuration_spec(model, specification; timeout = timeout)
    fields = resolution.detailed.fields
    ids = reduce(vcat, (request.fields for request in requests); init = FieldID[])
    for request in requests
        request.allowed_fields === nothing || append!(ids, request.allowed_fields)
    end
    labels = _field_labels(ids, fields)
    prefix = _configuration_spec_commands(model, specification, resolution)
    output_file = "bridge_effective_couplings.txt"
    commands = vcat(prefix, ["cd ..", "cd couplings"])
    for request in requests
        push!(commands, _coupling_command(request, labels))
        push!(commands, "wait(1)")
    end
    push!(commands, "print effective superpotential")
    push!(commands, "save couplings($output_file)")
    run = _run_model_script_artifacts(
        model,
        commands;
        collect_files = [output_file],
        timeout = timeout,
    )
    _validate_configuration_creation(run.output, specification)
    haskey(run.files, output_file) || throw(CouplingExecutionError(
        "upstream did not save ordinary couplings for effective parsing",
        run.output,
    ))
    source = run.files[output_file]
    source_terms = parse_couplings(source, model, fields)
    reported_count = _reported_coupling_count(run.output)
    reported_count == length(source_terms) || throw(CouplingExecutionError(
        "upstream reported $reported_count created couplings but saved $(length(source_terms)) terms",
        run.output,
    ))
    effective_output = output_for(split_transcript(run.output), "print effective superpotential")
    terms = parse_effective_couplings(effective_output, fields, source_terms)
    return EffectiveCouplingResult(
        specification,
        collect(requests),
        source_terms,
        terms,
        info,
        _sanitize_coupling_transcript(string(resolution.transcript, '\n', run.output)),
        source,
    )
end
