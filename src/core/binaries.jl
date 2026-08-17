using Preferences

const _VALID_MODES = (:susy, :nonsusy)

function _check_mode(mode::Symbol)
    mode in _VALID_MODES ||
        throw(ArgumentError("mode must be :susy or :nonsusy, got :$mode"))
    return mode
end

_binary_envvar(mode::Symbol) = mode === :susy ? "ORBIFOLDER_BIN" : "NONSUSYORBIFOLDER_BIN"
_geometry_envvar(mode::Symbol) = mode === :susy ? "ORBIFOLDER_GEOMETRY_DIR" : "NONSUSYORBIFOLDER_GEOMETRY_DIR"
_binary_prefkey(mode::Symbol) = mode === :susy ? "orbifolder_bin" : "nonsusyorbifolder_bin"
_geometry_prefkey(mode::Symbol) = mode === :susy ? "orbifolder_geometry_dir" : "nonsusyorbifolder_geometry_dir"

"""
    orbifolder_binary(mode::Symbol) -> String

Resolve the path to the `orbifolder` (`mode = :susy`) or `nonSUSYorbifolder`
(`mode = :nonsusy`) executable.

Resolution order: the environment variable (`ORBIFOLDER_BIN` /
`NONSUSYORBIFOLDER_BIN`), then a `Preferences.jl` setting stored via
[`set_orbifolder_binary!`](@ref), then a bare executable name on `PATH`.

Throws an `ErrorException` with build instructions if no usable binary is found.
See `docs/upstream_notes.md` for how to build the upstream tools.
"""
function orbifolder_binary(mode::Symbol)
    _check_mode(mode)
    path = get(ENV, _binary_envvar(mode), nothing)
    path === nothing && (path = @load_preference(_binary_prefkey(mode)))
    fallback_name = mode === :susy ? "orbifolder" : "nonSUSYorbifolder"
    path === nothing && (path = Sys.which(fallback_name))

    if path === nothing || !isfile(path)
        error(
            "Could not locate the $(mode === :susy ? "orbifolder" : "nonSUSYorbifolder") " *
            "executable. Build it from source (see docs/upstream_notes.md) and either " *
            "put it on PATH, set the environment variable $(_binary_envvar(mode)), or call " *
            "set_orbifolder_binary!(:$mode, \"/path/to/binary\")."
        )
    end
    return path
end

"""
    set_orbifolder_binary!(mode::Symbol, path::AbstractString)

Persist the path to the `orbifolder`/`nonSUSYorbifolder` executable for `mode`
(`:susy` or `:nonsusy`) as a `Preferences.jl` setting in the active project, so
it doesn't need to be set again in future Julia sessions.
"""
function set_orbifolder_binary!(mode::Symbol, path::AbstractString)
    _check_mode(mode)
    isfile(path) || throw(ArgumentError("no file at $path"))
    @set_preferences!(_binary_prefkey(mode) => String(path))
    return path
end

"""
    orbifolder_geometry_dir(mode::Symbol) -> String

Resolve the `Geometry/` directory (space-group definition files) that ships
with the upstream source tree for `mode`.

Resolution order: the environment variable (`ORBIFOLDER_GEOMETRY_DIR` /
`NONSUSYORBIFOLDER_GEOMETRY_DIR`), then a `Preferences.jl` setting stored via
[`set_orbifolder_geometry_dir!`](@ref), then a `Geometry` directory next to
[`orbifolder_binary`](@ref)`(mode)` (checking both the binary's own directory
and its parent, since the SUSY binary lives in `src/orbifolder/` under the
source tree while `Geometry/` sits at the tree root).
"""
function orbifolder_geometry_dir(mode::Symbol)
    _check_mode(mode)
    dir = get(ENV, _geometry_envvar(mode), nothing)
    dir === nothing && (dir = @load_preference(_geometry_prefkey(mode)))

    if dir === nothing
        bindir = dirname(orbifolder_binary(mode))
        # The nonSUSY binary sits at the source-tree root next to Geometry/;
        # the SUSY binary sits two levels down, in src/orbifolder/.
        for candidate in (
            joinpath(bindir, "Geometry"),
            joinpath(bindir, "..", "Geometry"),
            joinpath(bindir, "..", "..", "Geometry"),
        )
            if isdir(candidate)
                dir = candidate
                break
            end
        end
    end

    if dir === nothing || !isdir(dir)
        error(
            "Could not locate the Geometry/ directory for mode :$mode. Set the environment " *
            "variable $(_geometry_envvar(mode)), or call " *
            "set_orbifolder_geometry_dir!(:$mode, \"/path/to/Geometry\")."
        )
    end
    return dir
end

"""
    set_orbifolder_geometry_dir!(mode::Symbol, dir::AbstractString)

Persist the path to the `Geometry/` directory for `mode` (`:susy` or
`:nonsusy`) as a `Preferences.jl` setting in the active project.
"""
function set_orbifolder_geometry_dir!(mode::Symbol, dir::AbstractString)
    _check_mode(mode)
    isdir(dir) || throw(ArgumentError("no directory at $dir"))
    @set_preferences!(_geometry_prefkey(mode) => String(dir))
    return dir
end
