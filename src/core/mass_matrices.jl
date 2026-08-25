function _mass_matrix_error(message::AbstractString, source::AbstractString)
    throw(MassMatrixParseError(String(message), String(source)))
end

function _remove_external_fields(
    term::CouplingTerm,
    row::FieldID,
    column::FieldID,
)
    remaining = copy(term.fields)
    for external in (row, column)
        index = findfirst(==(external), remaining)
        index === nothing && return nothing
        deleteat!(remaining, index)
    end
    return remaining
end

function _parse_mass_matrix_entry(
    text::AbstractString,
    row::FieldID,
    column::FieldID,
    labels::Dict{String,FieldID},
    source_terms::AbstractVector{CouplingTerm},
    source::AbstractString,
)
    entry = strip(text)
    entry == "0" && return MassMatrixTerm[]
    occursin(r"^s(?:\^\d+)?$", entry) && _mass_matrix_error(
        "mass-matrix entry is order-abbreviated; request a sufficient max_order",
        source,
    )
    result = MassMatrixTerm[]
    for summand in split(entry, r"\s+\+\s+")
        tokens = getfield.(collect(eachmatch(r"<([^>]+)>", summand)), :captures)
        isempty(tokens) && _mass_matrix_error("malformed mass-matrix monomial: $summand", source)
        reconstructed = join(("<$(token[1])>" for token in tokens), " ")
        strip(summand) == reconstructed ||
            _mass_matrix_error("unrecognized mass-matrix monomial: $summand", source)
        names = [token[1] for token in tokens]
        unknown = filter(name -> !haskey(labels, name), names)
        isempty(unknown) || _mass_matrix_error(
            "mass matrix refers to unknown field label $(first(unknown))",
            source,
        )
        vevs = [labels[name] for name in names]
        candidates = filter(source_terms) do term
            remaining = _remove_external_fields(term, row, column)
            remaining !== nothing && _field_multiset(remaining) == _field_multiset(vevs)
        end
        length(candidates) == 1 || _mass_matrix_error(
            isempty(candidates) ?
            "mass-matrix monomial does not match a registered source coupling" :
            "mass-matrix monomial matches more than one registered source coupling",
            source,
        )
        push!(result, MassMatrixTerm(only(candidates), vevs))
    end
    return result
end

"""
    parse_mass_matrix(output, rows, columns, fields, source_terms)

Parse the plain-text result of SUSY orbifolder's explicit
`print mass matrix(...) max order(...)` command. The printed dimensions and
row/column orientation are validated, and every VEV monomial is matched to
exactly one registered ordinary coupling.
"""
function parse_mass_matrix(
    output::AbstractString,
    rows::AbstractVector{FieldID},
    columns::AbstractVector{FieldID},
    fields::AbstractVector{DetailedField},
    source_terms::AbstractVector{CouplingTerm};
    row_label::AbstractString = "R",
    column_label::AbstractString = "C",
)
    raw = String(output)
    header = match(
        r"mass matrix:\s+([^\s_]+)_i\s+M_ij\s+([^\s_]+)_j\s*\(\s*(\d+)\s+x\s+(\d+)\s+matrix\)",
        raw,
    )
    header === nothing && _mass_matrix_error("mass-matrix header not found", raw)
    printed_row, printed_column = header.captures[1], header.captures[2]
    nrows, ncolumns = parse(Int, header.captures[3]), parse(Int, header.captures[4])
    transposed = row_label != column_label &&
                 printed_row == column_label && printed_column == row_label
    expected = transposed ? (length(columns), length(rows)) : (length(rows), length(columns))
    valid_labels = (printed_row == row_label && printed_column == column_label) || transposed
    valid_labels || _mass_matrix_error("unexpected mass-matrix row or column label", raw)
    (nrows, ncolumns) == expected || _mass_matrix_error(
        "mass-matrix dimensions $nrows x $ncolumns do not match expected $(expected[1]) x $(expected[2])",
        raw,
    )
    actual_rows = transposed ? collect(columns) : collect(rows)
    actual_columns = transposed ? collect(rows) : collect(columns)
    body = raw[nextind(raw, header.offset + ncodeunits(header.match) - 1):end]
    lines = filter(line -> startswith(line, '\t'), split(body, '\n'; keepempty = false))
    length(lines) == nrows || _mass_matrix_error(
        "mass-matrix body has $(length(lines)) rows instead of $nrows",
        raw,
    )
    label_map = Dict(field.label => field.id for field in fields)
    entries = Matrix{Vector{MassMatrixTerm}}(undef, nrows, ncolumns)
    for i in 1:nrows
        cells = split(strip(lines[i]), r"\t+")
        length(cells) == ncolumns || _mass_matrix_error(
            "mass-matrix row $i has $(length(cells)) entries instead of $ncolumns",
            raw,
        )
        for j in 1:ncolumns
            entries[i, j] = _parse_mass_matrix_entry(
                cells[j], actual_rows[i], actual_columns[j], label_map, source_terms, raw,
            )
        end
    end
    return (; rows = actual_rows, columns = actual_columns, entries, transposed)
end

function _mass_matrix_labels(request::MassMatrixRequest, fields)
    original = _field_labels(vcat(request.rows, request.columns), fields)
    same_family = request.rows == request.columns
    labels = Dict(field.id => field.label for field in fields)
    changes = String[]
    for (i, field) in enumerate(request.rows)
        name = "R_$i"
        labels[field] = name
        push!(changes, "change label($(original[field])) to($name)")
    end
    unless_columns = same_family ? FieldID[] : request.columns
    for (i, field) in enumerate(unless_columns)
        name = "C_$i"
        labels[field] = name
        push!(changes, "change label($(original[field])) to($name)")
    end
    return (; labels, changes, row_label = "R", column_label = same_family ? "R" : "C")
end

"""
    compute_mass_matrix(model, specification, request; timeout = 120)

Replay a declarative SUSY VEV configuration, register the explicitly requested
ordinary couplings, and ask upstream to construct their effective mass matrix.
Rows and columns are selected with stable `FieldID`s; temporary family labels
exist only inside the isolated upstream process.
"""
function compute_mass_matrix(
    model::OrbifolderModel,
    specification::VEVConfigurationSpec,
    request::MassMatrixRequest;
    timeout::Real = 120,
)
    info = backend_info(model.mode; timeout = min(timeout, 30))
    supports(info, :mass_matrices) ||
        throw(ArgumentError("mass-matrix calculations are not supported by :$(model.mode)"))
    resolution = _resolve_configuration_spec(model, specification; timeout = timeout)
    fields = resolution.detailed.fields
    naming = _mass_matrix_labels(request, fields)
    ids = reduce(vcat, (coupling.fields for coupling in request.couplings); init = FieldID[])
    for coupling in request.couplings
        coupling.allowed_fields === nothing || append!(ids, coupling.allowed_fields)
    end
    all(haskey(naming.labels, id) for id in ids) || throw(ArgumentError(
        "a coupling request contains a field absent from the base configuration",
    ))
    prefix = _configuration_spec_commands(model, specification, resolution)
    output_file = "bridge_mass_matrix_couplings.txt"
    commands = vcat(prefix, ["cd labels"], naming.changes, ["cd ..", "cd ..", "cd couplings"])
    for coupling in request.couplings
        push!(commands, _coupling_command(coupling, naming.labels))
        push!(commands, "wait(1)")
    end
    push!(commands, "mass matrix($(naming.row_label) $(naming.column_label))")
    push!(commands, "print mass matrix(1) max order($(request.max_order))")
    push!(commands, "save couplings($output_file)")
    run = _run_model_script_artifacts(
        model, commands; collect_files = [output_file], timeout = timeout,
    )
    _validate_configuration_creation(run.output, specification)
    haskey(run.files, output_file) || throw(CouplingExecutionError(
        "upstream did not save mass-matrix source couplings", run.output,
    ))
    source = run.files[output_file]
    source_terms = parse_couplings(source, model, fields)
    _reported_coupling_count(run.output) == length(source_terms) ||
        throw(CouplingExecutionError("created and saved coupling counts disagree", run.output))
    command = "print mass matrix(1) max order($(request.max_order))"
    printed = output_for(split_transcript(run.output), command)
    # The parser needs the temporary labels that upstream prints for VEVs.
    renamed_fields = [
        DetailedField(
            field.id, get(naming.labels, field.id, field.label), field.rep,
            field.statistic, field.charges, field.multiplet_type, field.sector,
            field.constructing_translation, field.localization,
            field.space_group_charges, field.r_charges, field.right_moving_momentum,
        )
        for field in fields
    ]
    parsed = parse_mass_matrix(
        printed, request.rows, request.columns, renamed_fields, source_terms;
        row_label = naming.row_label, column_label = naming.column_label,
    )
    return MassMatrixResult(
        specification, request, parsed.rows, parsed.columns, parsed.entries,
        source_terms, parsed.transposed, info,
        _sanitize_coupling_transcript(string(resolution.transcript, '\n', run.output)), source,
    )
end
