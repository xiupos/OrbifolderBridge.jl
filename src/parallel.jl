# Run `commands` for each of `models` concurrently (asyncmap over
# process-launch-and-wait, which is I/O-bound: each call gets its own
# mktempdir via run_orbifolder_script, so concurrent calls never share
# files), then parse every raw transcript sequentially with `parser`.
#
# The split matters: GAP (used by the Phase 4 Oscar/GAP mapping layer) is
# not thread-safe, so nothing that might end up calling into GAP may run
# concurrently. Plain-text parsing (this function) doesn't touch GAP, but
# callers that go on to build Oscar objects from the results (e.g.
# `gauge_group_root_systems`, `field_weights`) must still do so in an
# ordinary sequential loop.
function _parallel_compute(
    models::AbstractVector{OrbifolderModel},
    commands::Vector{<:AbstractString},
    keyword::AbstractString,
    parser;
    config::Union{Nothing,VEVConfigurationRef} = nothing,
    ntasks::Int = 4,
    timeout::Real = 120,
)
    full_commands = _configuration_commands(config, commands)
    raws = asyncmap(m -> _run_model_script(m, full_commands; timeout = timeout), models; ntasks = ntasks)
    return map(raws) do output
        _validate_configuration_selection(output, config)
        parser(output_for(split_transcript(output), keyword))
    end
end

"""
    compute_spectra(models::AbstractVector{OrbifolderModel}; ntasks = 4, timeout = 120) -> Vector{Spectrum}

Parallel form of [`compute_spectrum`](@ref): runs up to `ntasks` `orbifolder`/
`nonSUSYorbifolder` subprocesses concurrently via `asyncmap` (each `model`
gets its own `mktempdir`, so runs never interfere with each other), then
parses every result sequentially.
"""
compute_spectra(
    models::AbstractVector{OrbifolderModel},
    config::Union{Nothing,VEVConfigurationRef} = nothing;
    ntasks::Int = 4,
    timeout::Real = 120,
) = _parallel_compute(
    models, ["cd spectrum", "print summary"], "print summary", parse_spectrum;
    config = config, ntasks = ntasks, timeout = timeout,
)

"""
    compute_gauge_groups(models::AbstractVector{OrbifolderModel}; ntasks = 4, timeout = 120) -> Vector{GaugeGroup}

Parallel form of [`compute_gauge_group`](@ref); see [`compute_spectra`](@ref)
for the concurrency model.
"""
compute_gauge_groups(
    models::AbstractVector{OrbifolderModel},
    config::Union{Nothing,VEVConfigurationRef} = nothing;
    ntasks::Int = 4,
    timeout::Real = 120,
) = _parallel_compute(
    models, ["cd gauge group", "print gauge group"], "print gauge group", parse_gauge_group;
    config = config, ntasks = ntasks, timeout = timeout,
)

"""
    compute_twists(models::AbstractVector{OrbifolderModel}; ntasks = 4, timeout = 120) -> Vector{Twist}

Parallel form of [`compute_twist`](@ref); see [`compute_spectra`](@ref) for
the concurrency model.
"""
compute_twists(models::AbstractVector{OrbifolderModel}; ntasks::Int = 4, timeout::Real = 120) =
    _parallel_compute(
        models, ["cd model", "print twist"], "print twist", parse_twist;
        ntasks = ntasks, timeout = timeout,
    )

"""
    compute_shift_vectors_batch(models::AbstractVector{OrbifolderModel}; ntasks = 4, timeout = 120) -> Vector{Vector{ShiftVector}}

Parallel form of [`compute_shift_vectors`](@ref); see [`compute_spectra`](@ref)
for the concurrency model.
"""
compute_shift_vectors_batch(
    models::AbstractVector{OrbifolderModel};
    ntasks::Int = 4,
    timeout::Real = 120,
) = _parallel_compute(
    models, ["cd model", "print shift"], "print shift", parse_shift_vectors;
    ntasks = ntasks, timeout = timeout,
)

"""
    compute_wilson_lines_batch(models::AbstractVector{OrbifolderModel}; ntasks = 4, timeout = 120) -> Vector{WilsonLines}

Parallel form of [`compute_wilson_lines`](@ref); see [`compute_spectra`](@ref)
for the concurrency model.
"""
compute_wilson_lines_batch(
    models::AbstractVector{OrbifolderModel};
    ntasks::Int = 4,
    timeout::Real = 120,
) = _parallel_compute(
    models, ["cd model", "print Wilson lines"], "print Wilson lines", parse_wilson_lines;
    ntasks = ntasks, timeout = timeout,
)
