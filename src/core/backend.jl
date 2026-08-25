const _SUPPORTED_BACKEND_VERSIONS = Dict(
    :susy => Set([v"1.2.1"]),
    :nonsusy => Set([v"1.0.0"]),
)

const _BACKEND_CAPABILITIES = Dict(
    (:susy, v"1.2.1") => (
        :consistency, :gauge_group, :spectrum, :detailed_spectrum,
        :twist, :shift_vectors, :wilson_lines, :raw_commands,
        :model_generation, :model_classification, :inequivalent_models,
        :coupling_refined_inequivalence, :anomaly_check, :vev_configurations,
        :vev_configuration_mutation, :field_vevs, :unbroken_gauge_group,
        :exact_gauge_data, :couplings, :mass_matrices,
    ),
    (:nonsusy, v"1.0.0") => (
        :consistency, :gauge_group, :spectrum, :detailed_spectrum,
        :twist, :shift_vectors, :wilson_lines, :raw_commands,
        :model_generation, :model_classification, :inequivalent_models,
        :anomaly_check, :vev_configurations, :vev_configuration_mutation,
        :exact_gauge_data,
    ),
)

"""
    BackendInfo

Detected information about one configured upstream backend. `kind` is
`:susy` or `:nonsusy`; `version` is parsed from the upstream startup banner.
`capabilities` lists operations supported by OrbifolderBridge for that
backend/version pair.
"""
struct BackendInfo
    kind::Symbol
    version::VersionNumber
    binary::String
    geometry_dir::String
    capabilities::Tuple{Vararg{Symbol}}
end
@structural_equality BackendInfo

"""
    BackendCompatibilityError <: Exception

Thrown when a configured executable, its startup banner, or its output version
is not supported. The captured `output` is retained for diagnosis.
"""
struct BackendCompatibilityError <: Exception
    message::String
    output::String
end

function Base.showerror(io::IO, e::BackendCompatibilityError)
    print(io, "BackendCompatibilityError: ", e.message)
end

"""
    BackendSelfTest

Result of [`check_backend`](@ref). Infrastructure and compatibility failures
are represented by `ok == false`; `message` describes the failure and
`output` retains any available diagnostic text.
"""
struct BackendSelfTest
    info::Union{BackendInfo,Nothing}
    ok::Bool
    message::String
    output::String
end
@structural_equality BackendSelfTest

function _parse_backend_banner(output::AbstractString)
    kind = if occursin(r"(?i)Non-SUSY Orbifolder", output)
        :nonsusy
    elseif occursin(r"The C\+\+ Orbifolder", output)
        :susy
    else
        throw(BackendCompatibilityError(
            "startup banner does not identify a supported backend",
            String(output),
        ))
    end

    m = match(r"(?im)^\s*#?\s*Version:\s*([0-9]+(?:\.[0-9]+)*)", output)
    m === nothing &&
        throw(BackendCompatibilityError("startup banner does not contain a version", String(output)))
    return kind, VersionNumber(m.captures[1])
end

function _validate_backend_output(expected_kind::Symbol, output::AbstractString)
    kind, version = _parse_backend_banner(output)
    kind === expected_kind || throw(BackendCompatibilityError(
        "configured :$expected_kind executable identifies itself as :$kind",
        String(output),
    ))
    version in _SUPPORTED_BACKEND_VERSIONS[kind] || throw(BackendCompatibilityError(
        "unsupported :$kind backend version $version; supported versions: " *
        join(sort!(collect(_SUPPORTED_BACKEND_VERSIONS[kind])), ", "),
        String(output),
    ))
    return version
end

function _check_backend_paths(mode::Symbol)
    # Both resolvers return absolute paths; see orbifolder_binary.
    binary = orbifolder_binary(mode)
    geometry_dir = orbifolder_geometry_dir(mode)
    (stat(binary).mode & 0o111) != 0 ||
        throw(BackendCompatibilityError("configured binary is not executable: $binary", ""))
    any(name -> startswith(name, "Geometry_") && endswith(name, ".txt"), readdir(geometry_dir)) ||
        throw(BackendCompatibilityError(
            "configured Geometry directory contains no Geometry_*.txt files: $geometry_dir",
            "",
        ))
    return binary, geometry_dir
end

function _probe_backend(mode::Symbol, binary::AbstractString, geometry_dir::AbstractString; timeout::Real)
    if mode === :susy
        return _run_orbifolder_script(mode, String[]; timeout = timeout)
    end

    return mktempdir() do dir
        symlink(geometry_dir, joinpath(dir, "Geometry"))
        command_file = "backend_self_test.txt"
        write(joinpath(dir, command_file), "exit\n")
        output = run_capture(Cmd(`$binary script $command_file`; dir = dir); timeout = timeout)
        result_file = joinpath(dir, "result_$command_file")
        isfile(result_file) || throw(BackendCompatibilityError(
            "non-SUSY backend self-test did not produce $result_file",
            output,
        ))
        return output
    end
end

# Probing the backend costs a full subprocess launch, and every public
# operation preflights through backend_info before doing its real work. Cache
# successful probes so a computation launches the binary once rather than
# twice, and a batch of N models launches it N times rather than 2N. The key
# includes the binary's mtime so a rebuilt backend is re-probed. Only
# successes are cached: a failure must stay reproducible on the next call.
const _BACKEND_INFO_CACHE = Dict{Tuple{Symbol,String,String,Float64},BackendInfo}()
const _BACKEND_INFO_CACHE_LOCK = ReentrantLock()

function _clear_backend_info_cache!()
    lock(_BACKEND_INFO_CACHE_LOCK) do
        empty!(_BACKEND_INFO_CACHE)
    end
    return nothing
end

"""
    backend_info(mode::Symbol; timeout::Real = 30, refresh::Bool = false) -> BackendInfo

Inspect and validate the configured upstream executable and `Geometry/`
directory. The executable is run through the same isolated script protocol as
normal computations. Unknown backend kinds and output versions fail with
[`BackendCompatibilityError`](@ref).

The configured paths, the executable bit, and the `Geometry/` inventory are
re-checked on every call, but a successful probe is cached per binary path and
modification time. Pass `refresh = true` to force the subprocess probe to run
again.
"""
function backend_info(mode::Symbol; timeout::Real = 30, refresh::Bool = false)
    _check_mode(mode)
    binary, geometry_dir = _check_backend_paths(mode)
    key = (mode, binary, geometry_dir, mtime(binary))
    if !refresh
        cached = lock(_BACKEND_INFO_CACHE_LOCK) do
            get(_BACKEND_INFO_CACHE, key, nothing)
        end
        cached === nothing || return cached
    end
    output = _probe_backend(mode, binary, geometry_dir; timeout = timeout)
    version = _validate_backend_output(mode, output)
    info = BackendInfo(mode, version, binary, geometry_dir, _BACKEND_CAPABILITIES[(mode, version)])
    lock(_BACKEND_INFO_CACHE_LOCK) do
        _BACKEND_INFO_CACHE[key] = info
    end
    return info
end

"""
    supports(info::BackendInfo, capability::Symbol) -> Bool

Return whether `capability` is supported by the detected backend/version.
"""
supports(info::BackendInfo, capability::Symbol) = capability in info.capabilities

"""
    check_backend(mode::Symbol; timeout::Real = 30) -> BackendSelfTest

Run a lightweight backend self-test using the real isolated script protocol.
Unlike [`backend_info`](@ref), expected configuration, process, and
compatibility failures are returned as a structured result.

This is a diagnostic, so it always re-probes the executable rather than
reusing a cached [`backend_info`](@ref) result.
"""
function check_backend(mode::Symbol; timeout::Real = 30)
    try
        info = backend_info(mode; timeout = timeout, refresh = true)
        return BackendSelfTest(info, true, "backend is compatible", "")
    catch e
        e isa InterruptException && rethrow()
        output = e isa BackendCompatibilityError ? e.output :
                 e isa OrbifolderProcessError ? string(e.stdout, e.stderr) : ""
        return BackendSelfTest(nothing, false, sprint(showerror, e), output)
    end
end
