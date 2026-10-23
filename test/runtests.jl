using Test
using OrbifolderBridge

# Runs `f` against the bundled JLL backend; skipped on platforms without a JLL build.
_with_jll_backend(f, mode::Symbol) =
    OrbifolderBridge._jll_module(mode).is_available() ? f() : nothing

@testset "OrbifolderBridge.jl" verbose = true begin
    include("test_core.jl")
    include("test_backend.jl")
    include("test_parsers.jl")
    include("test_oscar_mapping.jl")
    include("test_exact_gauge.jl")
    include("test_model.jl")
    include("test_geometry.jl")
    include("test_analysis.jl")
    include("test_configuration.jl")
    include("test_generation.jl")
    include("test_couplings.jl")
    include("test_mass_matrices.jl")
    include("test_consistency.jl")
    include("test_parallel.jl")
end
