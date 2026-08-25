const _ANALYSIS_ITEMS = (
    :gauge_group, :spectrum, :detailed_spectrum, :exact_gauge_data,
    :twist, :shift_vectors, :wilson_lines, :space_group_metadata, :localizations,
)

"""
    ComputationContext(model; config = nothing, timeout = 120)

Validated environment for an integrated upstream computation. The model,
backend, explicit VEV configuration, and execution timeout are fixed together
so every value in one [`AnalysisResult`](@ref) has the same scope.
"""
struct ComputationContext
    model::OrbifolderModel
    backend::BackendInfo
    config::Union{Nothing,VEVConfigurationRef}
    timeout::Float64

    function ComputationContext(
        model::OrbifolderModel,
        backend::BackendInfo,
        config::Union{Nothing,VEVConfigurationRef},
        timeout::Real,
    )
        backend.kind === model.mode || throw(ArgumentError(
            "backend kind :$(backend.kind) does not match model mode :$(model.mode)",
        ))
        value = Float64(timeout)
        isfinite(value) && value > 0 || throw(ArgumentError("timeout must be positive and finite"))
        return new(model, backend, config, value)
    end
end
@structural_equality ComputationContext

function ComputationContext(
    model::OrbifolderModel;
    config::Union{Nothing,VEVConfigurationRef} = nothing,
    timeout::Real = 120,
)
    backend = backend_info(model.mode; timeout = min(timeout, 30))
    return ComputationContext(model, backend, config, timeout)
end

"""Content identity of the selected upstream Geometry definition."""
struct GeometryIdentity
    file::String
    sha256::String
end
@structural_equality GeometryIdentity

"""
    AnalysisProvenance

Reproducibility metadata shared by all values in an integrated analysis.
Hashes are lowercase SHA-256 digests of the exact rendered model input and
selected Geometry-file contents. `transcript` is the complete upstream output.
"""
struct AnalysisProvenance
    backend::BackendInfo
    model_sha256::String
    geometry::GeometryIdentity
    configuration::Union{Nothing,VEVConfigurationRef}
    commands::Vector{String}
    warnings::Vector{String}
    transcript::String
end
@structural_equality AnalysisProvenance

"""Typed values obtained from one integrated upstream execution."""
struct AnalysisResult
    requested::Vector{Symbol}
    gauge_group::Union{Nothing,GaugeGroup}
    spectrum::Union{Nothing,Spectrum}
    detailed_spectrum::Union{Nothing,DetailedSpectrum}
    exact_gauge_data::Union{Nothing,ExactGaugeData}
    twist::Union{Nothing,Twist}
    shift_vectors::Union{Nothing,Vector{ShiftVector}}
    wilson_lines::Union{Nothing,WilsonLines}
    space_group_metadata::Union{Nothing,SpaceGroupMetadata}
    localizations::Union{Nothing,Vector{Localization}}
    provenance::AnalysisProvenance
end
@structural_equality AnalysisResult

"""Integrated parsing failure retaining the complete raw transcript."""
struct AnalysisParseError <: Exception
    item::Symbol
    message::String
    transcript::String
end

Base.showerror(io::IO, e::AnalysisParseError) =
    print(io, "AnalysisParseError while parsing :", e.item, ": ", e.message)

function _analysis_requested(include)
    requested = Symbol.(collect(include))
    isempty(requested) && throw(ArgumentError("include must contain at least one analysis item"))
    allunique(requested) || throw(ArgumentError("include contains duplicate analysis items"))
    unsupported = setdiff(requested, collect(_ANALYSIS_ITEMS))
    isempty(unsupported) || throw(ArgumentError(
        "unsupported analysis items: $(join(map(item -> ":$item", unsupported), ", "))",
    ))
    return requested
end

function _analysis_commands(requested::Vector{Symbol})
    wants(items...) = any(in(requested), items)
    commands = String[]
    if wants(:twist, :shift_vectors, :wilson_lines, :space_group_metadata)
        push!(commands, "cd model")
        wants(:twist) && push!(commands, "print twist")
        wants(:shift_vectors) && push!(commands, "print shift")
        wants(:wilson_lines) && push!(commands, "print Wilson lines")
        if wants(:space_group_metadata)
            append!(commands, ["print point group", "print space group"])
        end
        push!(commands, "cd ..")
    end
    if wants(:gauge_group, :exact_gauge_data)
        push!(commands, "cd gauge group", "print gauge group")
        wants(:exact_gauge_data) && append!(commands, ["print simple roots", "print U1 generators"])
        push!(commands, "cd ..")
    end
    if wants(:spectrum, :detailed_spectrum, :exact_gauge_data, :localizations)
        push!(commands, "cd spectrum", "print summary")
        if wants(:detailed_spectrum, :localizations)
            append!(commands, [
                "print(*) with internal information",
                "print summary of fixed points with labels",
            ])
        end
        push!(commands, "cd ..")
    end
    return commands
end

function _geometry_identity(context::ComputationContext)
    relative = context.model.space_group_file
    file = joinpath(context.backend.geometry_dir, basename(relative))
    isfile(file) || throw(BackendCompatibilityError(
        "selected Geometry file does not exist: $file", "",
    ))
    return GeometryIdentity(relative, bytes2hex(sha256(read(file))))
end

function _analysis_warnings(output::AbstractString)
    warnings = String[]
    for line in split(output, '\n')
        stripped = strip(line)
        occursin(r"(?i)^warning(?:\b|\s+in\b)", stripped) && push!(warnings, stripped)
    end
    return unique(warnings)
end

function _parse_analysis(
    context::ComputationContext,
    requested::Vector{Symbol},
    commands::Vector{String},
    output::AbstractString,
)
    pairs = split_transcript(output)
    wants(items...) = any(in(requested), items)
    parse_item(item, f) = try
        f()
    catch e
        e isa InterruptException && rethrow()
        throw(AnalysisParseError(item, sprint(showerror, e), String(output)))
    end

    summary = wants(:spectrum, :detailed_spectrum, :exact_gauge_data, :localizations) ?
        parse_item(:spectrum, () -> output_for(pairs, "print summary")) : nothing
    gauge_output = wants(:gauge_group, :exact_gauge_data) ?
        parse_item(:gauge_group, () -> output_for(pairs, "print gauge group")) : nothing
    detailed = wants(:detailed_spectrum, :localizations) ? parse_item(:detailed_spectrum, () ->
        parse_detailed_spectrum(
            summary,
            output_for(pairs, "print(*) with internal information"),
            output_for(pairs, "print summary of fixed points with labels"),
        )
    ) : nothing
    spectrum = summary === nothing ? nothing : parse_item(:spectrum, () -> parse_spectrum(summary))
    gauge = gauge_output === nothing ? nothing :
        parse_item(:gauge_group, () -> parse_gauge_group(gauge_output))
    exact = wants(:exact_gauge_data) ? parse_item(:exact_gauge_data, () ->
        parse_exact_gauge_data(
            gauge_output,
            output_for(pairs, "print simple roots"),
            output_for(pairs, "print U1 generators");
            spectrum_output = summary,
        )
    ) : nothing
    metadata = wants(:space_group_metadata) ? parse_item(:space_group_metadata, () ->
        parse_space_group_metadata(
            output_for(pairs, "print point group"), output_for(pairs, "print space group");
            backend = context.model.mode, geometry_file = context.model.space_group_file,
        )
    ) : nothing
    all_commands = vcat(
        ["load orbifolds($(_model_filename(context.model)))", "cd $(context.model.label)"],
        commands, ["exit"],
    )
    provenance = AnalysisProvenance(
        context.backend, bytes2hex(sha256(model_file_text(context.model))),
        _geometry_identity(context), context.config, all_commands,
        _analysis_warnings(output), String(output),
    )
    locations = wants(:localizations) ?
        parse_item(:localizations, () -> localizations(detailed)) : nothing
    return AnalysisResult(
        requested, gauge, spectrum, detailed, exact,
        wants(:twist) ? parse_item(:twist, () -> parse_twist(output_for(pairs, "print twist"))) : nothing,
        wants(:shift_vectors) ? parse_item(:shift_vectors, () -> parse_shift_vectors(output_for(pairs, "print shift"))) : nothing,
        wants(:wilson_lines) ? parse_item(:wilson_lines, () -> parse_wilson_lines(output_for(pairs, "print Wilson lines"))) : nothing,
        metadata, locations, provenance,
    )
end

"""
    analyze(context; include) -> AnalysisResult
    analyze(model; config = nothing, include, timeout = 120) -> AnalysisResult

Obtain related typed results in one isolated upstream run. Dependencies are
coalesced: for example localizations reuse the detailed spectrum, and exact
gauge data reuses the gauge-group and spectrum output.
"""
function analyze(context::ComputationContext; include)
    requested = _analysis_requested(include)
    commands = _configuration_commands(context.config, _analysis_commands(requested))
    output = _run_model_script(context.model, commands; timeout = context.timeout)
    _validate_configuration_selection(output, context.config)
    return _parse_analysis(context, requested, commands, output)
end

function analyze(
    model::OrbifolderModel;
    config::Union{Nothing,VEVConfigurationRef} = nothing,
    include,
    timeout::Real = 120,
)
    return analyze(ComputationContext(model; config = config, timeout = timeout); include = include)
end

"""
    analyze_batch(models; config = nothing, include, ntasks = 4, timeout = 120)

Run one integrated analysis per model concurrently in isolated directories.
Results retain input order and transcript parsing occurs after all executions.
"""
function analyze_batch(
    models::AbstractVector{OrbifolderModel};
    config::Union{Nothing,VEVConfigurationRef} = nothing,
    include,
    ntasks::Int = 4,
    timeout::Real = 120,
)
    ntasks > 0 || throw(ArgumentError("ntasks must be positive"))
    requested = _analysis_requested(include)
    isempty(models) && return AnalysisResult[]
    contexts = [ComputationContext(model; config = config, timeout = timeout) for model in models]
    commands = _configuration_commands(config, _analysis_commands(requested))
    outputs = asyncmap(contexts; ntasks = ntasks) do context
        _run_model_script(context.model, commands; timeout = context.timeout)
    end
    return map(contexts, outputs) do context, output
        _validate_configuration_selection(output, context.config)
        _parse_analysis(context, requested, commands, output)
    end
end
