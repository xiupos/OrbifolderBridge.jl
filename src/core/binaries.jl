using OrbiFolder_jll: OrbiFolder_jll
using NonSUSYOrbiFolder_jll: NonSUSYOrbiFolder_jll

const _VALID_MODES = (:susy, :nonsusy)

function _check_mode(mode::Symbol)
    mode in _VALID_MODES ||
        throw(ArgumentError("mode must be :susy or :nonsusy, got :$mode"))
    return mode
end

_binary_name(mode::Symbol) = mode === :susy ? "orbifolder" : "nonSUSYorbifolder"
_jll_module(mode::Symbol) = mode === :susy ? OrbiFolder_jll : NonSUSYOrbiFolder_jll

# On platforms without a JLL build, `is_available()` is false rather than a
# load error, so the JLLs are safe as unconditional dependencies.
function _available_jll(mode::Symbol)
    jll = _jll_module(mode)
    jll.is_available() || error(
        "No $(_binary_name(mode)) build is available for $(Sys.KERNEL) ($(Sys.ARCH)). " *
        "OrbifolderBridge supports Linux only, where $(_binary_name(mode)) is provided by " *
        "$(nameof(jll))."
    )
    return jll
end

# The JLL executable needs the environment its wrapper `Cmd` carries: dependency
# artifacts such as GSL are not on its RPATH.
function _orbifolder_withenv(mode::Symbol, cmd::Cmd)
    return addenv(cmd, getproperty(_available_jll(mode), Symbol(_binary_name(mode)))().env)
end

"""
    orbifolder_binary(mode::Symbol) -> String

Return the path to the `orbifolder` (`mode = :susy`) or `nonSUSYorbifolder`
(`mode = :nonsusy`) executable provided by `OrbiFolder_jll`/`NonSUSYOrbiFolder_jll`.

Throws an `ErrorException` on platforms without a JLL build. OrbifolderBridge
supports Linux only, because upstream does not build elsewhere.

# Examples
```julia
julia> orbifolder_binary(:susy)
"/home/user/.julia/artifacts/<hash>/bin/orbifolder"
```
"""
function orbifolder_binary(mode::Symbol)
    _check_mode(mode)
    return getproperty(_available_jll(mode), Symbol(_binary_name(mode), "_path"))
end

"""
    orbifolder_geometry_dir(mode::Symbol) -> String

Return the `Geometry/` directory (space-group definition files) bundled in the
JLL artifact for `mode`, next to the executable.
"""
function orbifolder_geometry_dir(mode::Symbol)
    _check_mode(mode)
    return joinpath(_available_jll(mode).artifact_dir, "bin", "Geometry")
end
