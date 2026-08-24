"""
    ConsistencyResult

Result of asking the upstream backend to load an [`OrbifolderModel`](@ref).

Fields:
- `valid`: whether loading and a lightweight `print shift` round trip succeeded
- `message`: a description of the result or the backend's rejection reason
- `output`: the raw backend transcript for debugging
"""
struct ConsistencyResult
    valid::Bool
    message::String
    output::String
end

Base.:(==)(a::ConsistencyResult, b::ConsistencyResult) =
    all(getfield(a, f) == getfield(b, f) for f in fieldnames(ConsistencyResult))
Base.hash(result::ConsistencyResult, h::UInt) =
    hash((result.valid, result.message, result.output), hash(ConsistencyResult, h))

# These phrases come from the model-loading paths in upstream COrbifoldGroup
# and CPrompt.  Keep this list deliberately narrow: an unknown diagnostic is
# an output/protocol failure, not evidence that a model is inconsistent.
const _MODEL_REJECTION_PATTERNS = Pair{Regex,String}[
    r"(?i)modular invariance (?:has )?failed" => "modular invariance failed",
    r"(?i)problems with modular invariance" => "modular invariance failed",
    r"(?i)relations between Wilson lines not fulfilled" => "Wilson-line relations are not fulfilled",
    r"(?i)cannot load shifts or Wilsonlines" => "shift or Wilson-line data could not be loaded",
    r"(?i)space group ill-defined" => "space group is ill-defined or incompatible",
    r"(?i)geometry-file .* is corrupt" => "space-group geometry is corrupt or incompatible",
    r"(?i)orbifold group ill-defined" => "orbifold group is ill-defined",
    r"(?i)orbifold \"[^\"]+\" not known" => "model label was not loaded by the backend",
]

function _rejection_reason(text::AbstractString)
    for (pattern, reason) in _MODEL_REJECTION_PATTERNS
        occursin(pattern, text) && return reason
    end
    return nothing
end

function _consistency_from_transcript(output::AbstractString)
    raw = String(output)
    reason = _rejection_reason(raw)
    reason === nothing || return ConsistencyResult(false, reason, raw)

    pairs = split_transcript(raw)
    shift_output = output_for(pairs, "print shift")
    shifts = parse_shift_vectors(shift_output)
    all(s -> length(s.vector) == 16, shifts) ||
        error("backend returned a non-16-dimensional shift vector")
    return ConsistencyResult(true, "model loaded and shift vectors were read back successfully", raw)
end

function _check_consistency(model::OrbifolderModel, runner; timeout::Real = 120)
    output = try
        runner(model, ["cd model", "print shift"]; timeout = timeout)
    catch e
        if e isa OrbifolderProcessError
            raw = string(e.stdout, isempty(e.stderr) ? "" : "\n", e.stderr)
            reason = _rejection_reason(raw)
            reason === nothing && rethrow()
            return ConsistencyResult(false, reason, raw)
        end
        rethrow()
    end
    return _consistency_from_transcript(output)
end

"""
    check_consistency(model::OrbifolderModel; timeout = 120) -> ConsistencyResult

Render `model` with [`model_file_text`](@ref), load it in the backend selected
by `model.mode`, enter its label and `model` directory, and run the lightweight
`print shift` command.  A backend-confirmed model rejection is returned as an
invalid result. Timeouts, missing binaries/Geometry data, process failures
without a recognized rejection, and unexpected transcript/parser failures are
thrown instead of being mislabeled as model inconsistency.
"""
check_consistency(model::OrbifolderModel; timeout::Real = 120) =
    _check_consistency(model, _run_model_script; timeout = timeout)

"""
    is_consistent(model::OrbifolderModel; timeout = 120) -> Bool

Return [`check_consistency`](@ref)`(model; timeout).valid`. Infrastructure,
timeout, and unexpected parsing errors propagate to the caller.
"""
is_consistent(model::OrbifolderModel; timeout::Real = 120) =
    check_consistency(model; timeout = timeout).valid

"""
    check_consistency_batch(models::AbstractVector{OrbifolderModel}; ntasks = 4,
                            timeout = 120) -> Vector{ConsistencyResult}

Check up to `ntasks` models concurrently, preserving input order. Explicit
backend rejections are ordinary invalid results; infrastructure and unexpected
internal failures propagate.
"""
function check_consistency_batch(
    models::AbstractVector{OrbifolderModel};
    ntasks::Integer = 4,
    timeout::Real = 120,
)
    ntasks > 0 || throw(ArgumentError("ntasks must be positive, got $ntasks"))
    return _check_consistency_batch(models, check_consistency; ntasks = ntasks, timeout = timeout)
end

function _check_consistency_batch(models, checker; ntasks::Integer = 4, timeout::Real = 120)
    ntasks > 0 || throw(ArgumentError("ntasks must be positive, got $ntasks"))
    return asyncmap(m -> checker(m; timeout = timeout), models; ntasks = Int(ntasks))
end

"""
    partition_consistent_models(models; ntasks = 4, timeout = 120) -> NamedTuple

Check `models` and return a named tuple containing `valid_models`,
`invalid_models`, and `results`, with all three derived in input order.
"""
function partition_consistent_models(
    models::AbstractVector{OrbifolderModel};
    ntasks::Integer = 4,
    timeout::Real = 120,
)
    results = check_consistency_batch(models; ntasks = ntasks, timeout = timeout)
    valid_models = [model for (model, result) in zip(models, results) if result.valid]
    invalid_models = [model for (model, result) in zip(models, results) if !result.valid]
    return (; valid_models, invalid_models, results)
end
