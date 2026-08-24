const _MODEL_CLASSES = (:sm, :pati_salam, :su5)
const _CLASS_COMMAND = Dict(:sm => "SM", :pati_salam => "PS", :su5 => "SU5")
const _CLASS_CONFIG_PREFIX = Dict(
    :sm => "SMConfig",
    :pati_salam => "PSConfig",
    :su5 => "SU5Config",
)

"""
    ModelClassification

Result of upstream's SM, Pati–Salam, and SU(5) analysis of the default VEV
configuration. `classes` contains the recognized model classes and
`configurations` maps each class to the configuration labels created by
upstream. The requested `generations` includes upstream's vector-like-exotics
condition; the bridge does not reproduce that predicate.
"""
struct ModelClassification
    classes::Vector{Symbol}
    configurations::Dict{Symbol,Vector{String}}
    generations::Int
    backend::BackendInfo
    transcript::String
end

"""
    AnomalyReport

Structured status of upstream's anomaly diagnostics. `universal` is true only
when upstream explicitly reports universal anomaly ratios. The complete
diagnostic block remains available as `output`.
"""
struct AnomalyReport
    universal::Bool
    backend::BackendInfo
    output::String
end

"""
    GenerationDiagnostic

A warning or rejection reason explicitly reported by upstream during model
generation. `kind` is `:warning`, `:error`, or `:rejection`; `message` retains
the upstream wording. Candidates rejected without an upstream message cannot
be represented individually.
"""
struct GenerationDiagnostic
    kind::Symbol
    message::String
end

"""
    ModelGenerationRequest

Declarative options for upstream random-model generation. `inherit` contains
eight booleans for two compactification-shift slots followed by six Wilson
lines; `true` inherits the source value and `false` randomizes it. non-SUSY's
additional Witten shift is always inherited. At least one entry must be false.
`classes` may contain `:sm`, `:pati_salam`, and `:su5`.
`generations` activates upstream's net-generation and vector-like-exotics
filter and therefore requires a nonempty `classes`. Coupling-refined
inequivalence is supported only by the SUSY backend.
"""
struct ModelGenerationRequest
    count::Int
    inherit::NTuple{8,Bool}
    classes::Vector{Symbol}
    generations::Union{Nothing,Int}
    inequivalent::Bool
    compare_couplings_through::Union{Nothing,Int}
    check_anomalies::Bool
end

function ModelGenerationRequest(;
    count::Integer = 1,
    inherit = (false, false, false, false, false, false, false, false),
    classes::AbstractVector{Symbol} = Symbol[],
    generations::Union{Nothing,Integer} = nothing,
    inequivalent::Bool = false,
    compare_couplings_through::Union{Nothing,Integer} = nothing,
    check_anomalies::Bool = true,
)
    count > 0 || throw(ArgumentError("count must be positive, got $count"))
    length(inherit) == 8 || throw(ArgumentError("inherit must contain eight booleans"))
    inherited = ntuple(i -> Bool(inherit[i]), 8)
    all(inherited) && throw(ArgumentError("at least one shift or Wilson line must be randomized"))
    unique_classes = unique(classes)
    all(c -> c in _MODEL_CLASSES, unique_classes) ||
        throw(ArgumentError("classes may contain only :sm, :pati_salam, and :su5"))
    generations === nothing || generations >= 0 ||
        throw(ArgumentError("generations must be nonnegative"))
    generations !== nothing && isempty(unique_classes) &&
        throw(ArgumentError("a generations filter requires at least one model class"))
    compare_couplings_through === nothing || compare_couplings_through >= 3 ||
        throw(ArgumentError("compare_couplings_through must be at least 3"))
    return ModelGenerationRequest(
        Int(count),
        inherited,
        unique_classes,
        generations === nothing ? nothing : Int(generations),
        inequivalent || compare_couplings_through !== nothing,
        compare_couplings_through === nothing ? nothing : Int(compare_couplings_through),
        check_anomalies,
    )
end

"""
    ModelGenerationResult

Models accepted and saved by upstream together with its diagnostics, the
effective request, backend information, and sanitized transcript. Upstream
does not expose a controllable random seed or a reason for every rejected
candidate, so `diagnostics` contains only messages actually reported.
"""
struct ModelGenerationResult
    models::Vector{OrbifolderModel}
    request::ModelGenerationRequest
    diagnostics::Vector{GenerationDiagnostic}
    backend::BackendInfo
    transcript::String
end

for T in (
    :ModelClassification,
    :AnomalyReport,
    :GenerationDiagnostic,
    :ModelGenerationRequest,
    :ModelGenerationResult,
)
    @eval begin
        Base.:(==)(a::$T, b::$T) = all(getfield(a, f) == getfield(b, f) for f in fieldnames($T))
        Base.hash(a::$T, h::UInt) = hash(ntuple(i -> getfield(a, i), fieldcount($T)), hash($T, h))
    end
end

_sanitized_generation_transcript(text::AbstractString) =
    replace(String(text), r"PID\s+[0-9]+" => "PID <redacted>")

function _classification_from_output(
    output::AbstractString,
    generations::Int,
    backend::BackendInfo,
)
    configs = Dict{Symbol,Vector{String}}()
    for class in _MODEL_CLASSES
        prefix = _CLASS_CONFIG_PREFIX[class]
        labels = unique(m.match for m in eachmatch(Regex("$(prefix)[0-9]+"), output))
        isempty(labels) || (configs[class] = labels)
    end
    return ModelClassification(
        collect(keys(configs)),
        configs,
        generations,
        backend,
        String(output),
    )
end

"""
    classify_model(model::OrbifolderModel; generations::Integer = 3, timeout = 120)

Ask upstream to classify the model's default VEV configuration as SM,
Pati–Salam, or SU(5), including its net-generation and vector-like-exotics
predicate.
"""
function classify_model(
    model::OrbifolderModel;
    generations::Integer = 3,
    timeout::Real = 120,
)
    generations >= 0 || throw(ArgumentError("generations must be nonnegative"))
    info = backend_info(model.mode; timeout = min(timeout, 30))
    command = "analyze config $(Int(generations))generations"
    output = _run_model_script(model, ["cd vev-config", command]; timeout = timeout)
    block = output_for(split_transcript(output), command)
    return _classification_from_output(block, Int(generations), info)
end

"""
    compute_anomaly_report(model::OrbifolderModel; timeout = 120) -> AnomalyReport

Return the anomaly diagnostics computed by upstream for the default VEV
configuration.
"""
function compute_anomaly_report(model::OrbifolderModel; timeout::Real = 120)
    info = backend_info(model.mode; timeout = min(timeout, 30))
    output = _run_model_script(model, ["cd gauge group", "print anomaly info"]; timeout = timeout)
    block = output_for(split_transcript(output), "print anomaly info")
    return _anomaly_report_from_output(block, info)
end

function _anomaly_report_from_output(output::AbstractString, backend::BackendInfo)
    universal = occursin("All anomalies are universal", output)
    nonuniversal = occursin("Anomalies are not universal", output)
    (universal || nonuniversal) || error("unrecognized anomaly diagnostic:\n$output")
    return AnomalyReport(universal, backend, String(output))
end

function _generation_command(source::OrbifolderModel, request::ModelGenerationRequest, filename::String)
    criteria = [_CLASS_COMMAND[c] for c in request.classes]
    request.inequivalent && push!(criteria, "inequivalent")
    request.generations === nothing || push!(criteria, "$(request.generations)generations")
    parts = ["create random orbifold from($(source.label))"]
    isempty(criteria) || push!(parts, "if($(join(criteria, ' ')))")
    push!(parts, "save to($filename)")
    push!(parts, "#models($(request.count))")
    push!(parts, "use($(join(Int.(request.inherit), ',')))")
    request.check_anomalies || push!(parts, "do not check anomalies")
    request.compare_couplings_through === nothing ||
        push!(parts, "compare #couplings of order($(request.compare_couplings_through))")
    return join(parts, ' ')
end

function _reported_diagnostics(output::AbstractString)
    diagnostics = GenerationDiagnostic[]
    for line in split(output, '\n')
        stripped = strip(line)
        kind = if startswith(stripped, "Warning")
            :warning
        elseif startswith(stripped, "Error")
            :error
        elseif occursin(r"^(Cannot|No models?)\b", stripped) ||
               occursin(r"(?i)\bproblems? with\b|\bwith problems?\b", stripped)
            :rejection
        end
        kind === nothing || push!(diagnostics, GenerationDiagnostic(kind, stripped))
    end
    return unique(diagnostics)
end

"""
    generate_models(source::OrbifolderModel, request::ModelGenerationRequest; timeout = 120)

Run upstream's random-model generator and return the accepted models. Random
choices are made and seeded inside upstream; OrbifolderBridge records the
request and result but cannot promise replay of the same candidates.
"""
function generate_models(
    source::OrbifolderModel,
    request::ModelGenerationRequest;
    timeout::Real = 120,
)
    info = backend_info(source.mode; timeout = min(timeout, 30))
    request.compare_couplings_through !== nothing &&
        !supports(info, :coupling_refined_inequivalence) &&
        throw(ArgumentError("coupling-refined inequivalence is not supported by :$(source.mode)"))

    input_file = _model_filename(source)
    output_file = "generated_models.txt"
    command = _generation_command(source, request, output_file)
    result = _run_orbifolder_script_artifacts(
        source.mode,
        ["load orbifolds($input_file)", command, "wait(1)"];
        files = Dict(input_file => model_file_text(source)),
        collect_files = [output_file],
        timeout = timeout,
    )
    model_text = get(result.files, output_file, "")
    models = isempty(strip(model_text)) ? OrbifolderModel[] :
             parse_orbifolder_models(model_text; mode = source.mode)
    transcript = _sanitized_generation_transcript(result.output)
    return ModelGenerationResult(
        models,
        request,
        _reported_diagnostics(transcript),
        info,
        transcript,
    )
end

"""
    select_inequivalent_models(models; compare_couplings_through = nothing, timeout = 120)

Ask upstream to retain spectrum-inequivalent models. On the SUSY backend the
comparison can additionally use coupling counts through an order of at least
three. All input models must use the same backend and have distinct labels.
"""
function select_inequivalent_models(
    models::AbstractVector{OrbifolderModel};
    compare_couplings_through::Union{Nothing,Integer} = nothing,
    timeout::Real = 120,
)
    isempty(models) && return OrbifolderModel[]
    mode = first(models).mode
    all(m -> m.mode === mode, models) ||
        throw(ArgumentError("all models must use the same backend"))
    allunique(m.label for m in models) ||
        throw(ArgumentError("model labels must be distinct"))
    compare_couplings_through === nothing || compare_couplings_through >= 3 ||
        throw(ArgumentError("compare_couplings_through must be at least 3"))
    info = backend_info(mode; timeout = min(timeout, 30))
    compare_couplings_through !== nothing &&
        !supports(info, :coupling_refined_inequivalence) &&
        throw(ArgumentError("coupling-refined inequivalence is not supported by :$mode"))

    input_file = "candidate_models.txt"
    output_file = "inequivalent_models.txt"
    option = "inequivalent"
    compare_couplings_through === nothing ||
        (option *= " compare #couplings of order($(Int(compare_couplings_through)))")
    result = _run_orbifolder_script_artifacts(
        mode,
        ["load orbifolds($input_file) $option", "save orbifolds($output_file)"];
        files = Dict(input_file => join(model_file_text.(models))),
        collect_files = [output_file],
        timeout = timeout,
    )
    haskey(result.files, output_file) ||
        error("backend did not save inequivalent models")
    return parse_orbifolder_models(result.files[output_file]; mode = mode)
end
