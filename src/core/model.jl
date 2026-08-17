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
    wilson_lines::Vector{Vector{Rational{Int}}}
end

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
- `shift`: either a single 16-entry vector \$V_1\$ (for \$\\mathbb{Z}_M\$ point
  groups), or a pair `(V_1, V_2)` of 16-entry vectors (for \$\\mathbb{Z}_M
  \\times \\mathbb{Z}_N\$ point groups); the unused second shift defaults to
  zero
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

    shift1, shift2 = if shift isa Tuple
        length(shift) == 2 || throw(ArgumentError("shift tuple must have length 2, got $(length(shift))"))
        _validate_vector16("shift[1]", shift[1]), _validate_vector16("shift[2]", shift[2])
    else
        _validate_vector16("shift", shift), zeros(Rational{Int}, 16)
    end

    length(wilson_lines) <= 6 ||
        throw(ArgumentError("wilson_lines must have at most 6 entries, got $(length(wilson_lines))"))
    wl = [_validate_vector16("wilson_lines[$i]", w) for (i, w) in enumerate(wilson_lines)]
    append!(wl, [zeros(Rational{Int}, 16) for _ in 1:(6-length(wl))])

    return OrbifolderModel(mode, String(label), "Geometry/Geometry_$(point_group).txt", lattice, shift1, shift2, wl)
end

_format_rational(r::Rational{Int}) = "$(numerator(r))/$(denominator(r))"
_format_vector16(v::Vector{Rational{Int}}) = join(_format_rational.(v), " ")

"""
    model_file_text(model::OrbifolderModel) -> String

Render `model` in the upstream `begin model ... end model` file format
expected by the `load orbifolds(...)` command.
"""
function model_file_text(model::OrbifolderModel)
    lines = [
        "begin model",
        "Label:$(model.label)",
        "SpaceGroup:$(model.space_group_file)",
        "Lattice:$(_LATTICE_KEYWORD[model.lattice])",
        "Shifts and Wilsonlines:",
        _format_vector16(model.shift1),
        _format_vector16(model.shift2),
        (_format_vector16(w) for w in model.wilson_lines)...,
        "end model",
    ]
    return join(lines, '\n') * '\n'
end

_model_filename(model::OrbifolderModel) = "model_$(model.label).txt"

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
    compute_gauge_group(model::OrbifolderModel; timeout = 120) -> GaugeGroup

Run `model` through the `orbifolder`/`nonSUSYorbifolder` backend and parse
its four-dimensional gauge group in the backend's default vev-configuration
(`"TestConfig1"`; switching vev-configurations is not yet supported, see
`docs/src/upstream_notes.md`).
"""
function compute_gauge_group(model::OrbifolderModel; timeout::Real = 120)
    out = _run_model_script(model, ["cd gauge group", "print gauge group"]; timeout = timeout)
    return parse_gauge_group(output_for(split_transcript(out), "print gauge group"))
end

"""
    compute_spectrum(model::OrbifolderModel; timeout = 120) -> Spectrum

Run `model` through the `orbifolder`/`nonSUSYorbifolder` backend and parse
its massless spectrum in the backend's default vev-configuration
(`"TestConfig1"`; switching vev-configurations is not yet supported, see
`docs/src/upstream_notes.md`).
"""
function compute_spectrum(model::OrbifolderModel; timeout::Real = 120)
    out = _run_model_script(model, ["cd spectrum", "print summary"]; timeout = timeout)
    return parse_spectrum(output_for(split_transcript(out), "print summary"))
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
`model.shift1`/`model.shift2`).
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
