const _LATTICE_KEYWORD = Dict(:E8xE8 => "E8xE8", :Spin32 => "Spin32")

"""
    OrbifolderModel

A heterotic orbifold model: a point group (via a specific space-group file),
a choice of ten-dimensional gauge lattice, up to two 16D shift vectors, and
six 16D Wilson lines. This is the Julia-side counterpart of the upstream
`begin model ... end model` file format (see `docs/src/upstream_notes.md`).

Construct with the keyword constructor below rather than calling this
directly.
"""
struct OrbifolderModel
    mode::Symbol
    label::String
    space_group_file::String
    lattice::Symbol
    shift1::Vector{Rational{Int}}
    shift2::Vector{Rational{Int}}
    shift3::Vector{Rational{Int}}
    wilson_lines::Vector{Vector{Rational{Int}}}
end
@structural_equality OrbifolderModel

function _validate_vector16(name::AbstractString, v::AbstractVector)
    length(v) == 16 || throw(ArgumentError("$name must have length 16, got $(length(v))"))
    return Rational{Int}.(v)
end

"""
    OrbifolderModel(; mode, label, point_group, shift, lattice = :E8xE8,
                     wilson_lines = fill(zeros(Int, 16), 6))

Construct an [`OrbifolderModel`](@ref).

- `mode`: `:susy` (the `orbifolder` backend) or `:nonsusy` (`nonSUSYorbifolder`)
- `label`: the model label passed to `Label:` in the model file
- `point_group`: the name of a shipped space-group file, e.g. `"Z3_1_1"` or
  `"Z3xZ3_1_1"`, resolved to `Geometry/Geometry_<point_group>.txt` in
  [`orbifolder_geometry_dir`](@ref)`(mode)`
- `shift`: for `mode = :susy`, either a single 16-entry vector \$V_1\$ (for a
  \$\\mathbb{Z}_M\$ point group) or a pair `(V_1, V_2)` (for
  \$\\mathbb{Z}_M \\times \\mathbb{Z}_N\$). For `mode = :nonsusy`, the pair
  follows upstream's three shift slots: the Witten \$\\mathbb{Z}_2\$ embedding
  followed by up to two compactification point-group embeddings. A single
  vector fills the first slot and leaves the remaining slots zero.
- `lattice`: `:E8xE8` or `:Spin32` (the \$E_8 \\times E_8\$ or
  \$\\mathrm{Spin}(32)/\\mathbb{Z}_2\$ ten-dimensional gauge lattice)
- `wilson_lines`: up to six 16-entry vectors \$W_1,\\dots,W_6\$; defaults to
  all zero. Fewer than six may be given, and the rest are zero-filled.
"""
function OrbifolderModel(;
    mode::Symbol,
    label::AbstractString,
    point_group::AbstractString,
    shift,
    lattice::Symbol = :E8xE8,
    wilson_lines::AbstractVector = Vector{Rational{Int}}[],
)
    _check_mode(mode)
    haskey(_LATTICE_KEYWORD, lattice) ||
        throw(ArgumentError("lattice must be :E8xE8 or :Spin32, got :$lattice"))

    max_shifts = mode === :susy ? 2 : 3
    shifts = shift isa Tuple ? collect(shift) : [shift]
    1 <= length(shifts) <= max_shifts || throw(ArgumentError(
        "shift must contain between 1 and $max_shifts vectors for mode :$mode, got $(length(shifts))",
    ))
    parsed_shifts = [
        i <= length(shifts) ? _validate_vector16("shift[$i]", shifts[i]) :
        zeros(Rational{Int}, 16)
        for i in 1:3
    ]

    length(wilson_lines) <= 6 ||
        throw(ArgumentError("wilson_lines must have at most 6 entries, got $(length(wilson_lines))"))
    wl = [_validate_vector16("wilson_lines[$i]", w) for (i, w) in enumerate(wilson_lines)]
    append!(wl, [zeros(Rational{Int}, 16) for _ in 1:(6-length(wl))])

    return OrbifolderModel(
        mode,
        String(label),
        "Geometry/Geometry_$(point_group).txt",
        lattice,
        parsed_shifts[1],
        parsed_shifts[2],
        parsed_shifts[3],
        wl,
    )
end

_format_rational(r::Rational{Int}) = "$(numerator(r))/$(denominator(r))"
_format_vector16(v::Vector{Rational{Int}}) = join(_format_rational.(v), " ")

"""
    model_file_text(model::OrbifolderModel) -> String

Render `model` in the upstream `begin model ... end model` file format
expected by the `load orbifolds(...)` command.
"""
function model_file_text(model::OrbifolderModel)
    shifts = model.mode === :susy ? [model.shift1, model.shift2] :
             [model.shift1, model.shift2, model.shift3]
    lines = [
        "begin model",
        "Label:$(model.label)",
        "SpaceGroup:$(model.space_group_file)",
        "Lattice:$(_LATTICE_KEYWORD[model.lattice])",
        "Shifts and Wilsonlines:",
        (_format_vector16(v) for v in shifts)...,
        (_format_vector16(w) for w in model.wilson_lines)...,
        "end model",
    ]
    return join(lines, '\n') * '\n'
end

_model_filename(model::OrbifolderModel) = "model_$(model.label).txt"

"""
    UpstreamModelParseError <: Exception

Thrown when an upstream model file does not match the supported
`begin model ... end model` grammar. The complete source `text` is retained
for diagnosis.
"""
struct UpstreamModelParseError <: Exception
    message::String
    text::String
end

Base.showerror(io::IO, e::UpstreamModelParseError) =
    print(io, "UpstreamModelParseError: ", e.message)

function _parse_model_vector(line::AbstractString, text::AbstractString)
    tokens = filter(!isempty, split(strip(line), r"[\s,]+"))
    length(tokens) == 16 || throw(UpstreamModelParseError(
        "shift and Wilson-line vectors must contain 16 entries, got $(length(tokens))",
        String(text),
    ))
    try
        return parse_rational.(tokens)
    catch e
        e isa InterruptException && rethrow()
        throw(UpstreamModelParseError("invalid rational in shift or Wilson-line vector", String(text)))
    end
end

"""
    parse_orbifolder_models(text::AbstractString; mode::Symbol) -> Vector{OrbifolderModel}

Parse one or more upstream `begin model ... end model` blocks. SUSY files
contain two shifts and six Wilson lines; non-SUSY files contain its Witten
shift, two compactification-shift slots, and six Wilson lines. Zero-valued
trailing vectors are accepted, while nonzero or malformed trailing data is
rejected.
"""
function parse_orbifolder_models(text::AbstractString; mode::Symbol)
    _check_mode(mode)
    raw = String(text)
    block_pattern = r"(?ms)^\s*begin model\s*$\n(.*?)^\s*end model\s*$"
    matches = collect(eachmatch(block_pattern, raw))
    blocks = [m.captures[1] for m in matches]
    isempty(blocks) && throw(UpstreamModelParseError("no complete model blocks found", raw))
    isempty(strip(replace(raw, block_pattern => ""))) || throw(UpstreamModelParseError(
        "unsupported text outside model blocks",
        raw,
    ))

    models = OrbifolderModel[]
    for block in blocks
        label_match = match(r"(?m)^\s*Label:\s*(\S.*?)\s*$", block)
        space_match = match(r"(?m)^\s*SpaceGroup:\s*(\S.*?)\s*$", block)
        lattice_match = match(r"(?m)^\s*Lattice:\s*(\S+)\s*$", block)
        marker = match(r"(?m)^\s*Shifts and Wilsonlines:\s*$", block)
        any(isnothing, (label_match, space_match, lattice_match, marker)) &&
            throw(UpstreamModelParseError("model block is missing a required header", raw))

        lattice = lattice_match.captures[1] == "E8xE8" ? :E8xE8 :
                  lattice_match.captures[1] == "Spin32" ? :Spin32 : nothing
        lattice === nothing && throw(UpstreamModelParseError(
            "unsupported lattice $(lattice_match.captures[1])",
            raw,
        ))

        vector_text = block[nextind(block, marker.offset + ncodeunits(marker.match) - 1):end]
        lines = filter(line -> !isempty(strip(line)), split(vector_text, '\n'))
        required_vectors = mode === :susy ? 8 : 9
        length(lines) >= required_vectors || throw(UpstreamModelParseError(
            "model block contains fewer than the required shift and Wilson-line vectors",
            raw,
        ))
        vectors = [_parse_model_vector(line, raw) for line in lines]
        all(v -> all(iszero, v), vectors[required_vectors+1:end]) ||
            throw(UpstreamModelParseError(
                "model block contains unsupported nonzero trailing vector data",
                raw,
            ))
        shift3 = mode === :nonsusy ? vectors[3] : zeros(Rational{Int}, 16)
        wilson_start = mode === :nonsusy ? 4 : 3
        push!(models, OrbifolderModel(
            mode,
            strip(label_match.captures[1]),
            strip(space_match.captures[1]),
            lattice,
            vectors[1],
            vectors[2],
            shift3,
            vectors[wilson_start:wilson_start+5],
        ))
    end
    return models
end

# Run `commands` after loading `model`, and return the raw transcript.
function _run_model_script(model::OrbifolderModel, commands::Vector{<:AbstractString}; timeout::Real = 120)
    filename = _model_filename(model)
    all_commands = vcat(["load orbifolds($filename)", "cd $(model.label)"], commands)
    return run_orbifolder_script(
        model.mode,
        all_commands;
        files = Dict(filename => model_file_text(model)),
        timeout = timeout,
    )
end

"""
    compute_gauge_group(model::OrbifolderModel[, config]; timeout = 120) -> GaugeGroup

Run `model` through the `orbifolder`/`nonSUSYorbifolder` backend and parse
its four-dimensional gauge group. Pass a [`VEVConfigurationRef`](@ref) as
`config` to select it explicitly. Omitting `config` preserves the legacy
behavior of using the backend's initially selected configuration.
"""
function compute_gauge_group(
    model::OrbifolderModel,
    config::Union{Nothing,VEVConfigurationRef} = nothing;
    timeout::Real = 120,
)
    commands = _configuration_commands(config, ["cd gauge group", "print gauge group"])
    out = _run_model_script(model, commands; timeout = timeout)
    _validate_configuration_selection(out, config)
    return parse_gauge_group(output_for(split_transcript(out), "print gauge group"))
end

"""
    compute_spectrum(model::OrbifolderModel[, config]; timeout = 120) -> Spectrum

Run `model` through the `orbifolder`/`nonSUSYorbifolder` backend and parse
its massless spectrum. Pass a [`VEVConfigurationRef`](@ref) to make the
configuration selection explicit; omission retains the legacy backend-default
behavior.
"""
function compute_spectrum(
    model::OrbifolderModel,
    config::Union{Nothing,VEVConfigurationRef} = nothing;
    timeout::Real = 120,
)
    commands = _configuration_commands(config, ["cd spectrum", "print summary"])
    out = _run_model_script(model, commands; timeout = timeout)
    _validate_configuration_selection(out, config)
    return parse_spectrum(output_for(split_transcript(out), "print summary"))
end

"""
    compute_detailed_spectrum(model::OrbifolderModel[, config]; timeout = 120) -> DetailedSpectrum

Run one backend session and obtain both the grouped spectrum and individually
identified fields, including sectors, constructing elements, localization,
discrete charges, R charges, and multiplet types where upstream exposes them.
Field labels refer to the explicitly selected `config`, or to the backend's
initial selection when it is omitted for backwards compatibility.
"""
function compute_detailed_spectrum(
    model::OrbifolderModel,
    config::Union{Nothing,VEVConfigurationRef} = nothing;
    timeout::Real = 120,
)
    commands = _configuration_commands(config, [
        "cd spectrum",
        "print summary",
        "print(*) with internal information",
        "print summary of fixed points with labels",
    ])
    output = _run_model_script(model, commands; timeout = timeout)
    _validate_configuration_selection(output, config)
    pairs = split_transcript(output)
    return parse_detailed_spectrum(
        output_for(pairs, "print summary"),
        output_for(pairs, "print(*) with internal information"),
        output_for(pairs, "print summary of fixed points with labels"),
    )
end

"""
    compute_twist(model::OrbifolderModel; timeout = 120) -> Twist

Run `model` through the backend and parse its point-group twist vector(s).
"""
function compute_twist(model::OrbifolderModel; timeout::Real = 120)
    out = _run_model_script(model, ["cd model", "print twist"]; timeout = timeout)
    return parse_twist(output_for(split_transcript(out), "print twist"))
end

"""
    compute_shift_vectors(model::OrbifolderModel; timeout = 120) -> Vector{ShiftVector}

Run `model` through the backend and parse its shift vector(s) as reported by
the backend (which may differ in presentation, though not value, from
the applicable `model.shift1`/`model.shift2`/`model.shift3` values).
"""
function compute_shift_vectors(model::OrbifolderModel; timeout::Real = 120)
    out = _run_model_script(model, ["cd model", "print shift"]; timeout = timeout)
    return parse_shift_vectors(output_for(split_transcript(out), "print shift"))
end

"""
    compute_wilson_lines(model::OrbifolderModel; timeout = 120) -> WilsonLines

Run `model` through the backend and parse its Wilson lines, including the
identifications and allowed orders imposed by the point group.
"""
function compute_wilson_lines(model::OrbifolderModel; timeout::Real = 120)
    out = _run_model_script(model, ["cd model", "print Wilson lines"]; timeout = timeout)
    return parse_wilson_lines(output_for(split_transcript(out), "print Wilson lines"))
end
