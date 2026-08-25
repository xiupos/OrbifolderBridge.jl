using Test
using OrbifolderBridge

@testset "OrbifolderBridge.jl" verbose = true begin
    include("test_core.jl")
    include("test_backend.jl")
    include("test_parsers.jl")
    include("test_oscar_mapping.jl")
    include("test_exact_gauge.jl")
    include("test_model.jl")
    include("test_configuration.jl")
    include("test_generation.jl")
    include("test_consistency.jl")
    include("test_parallel.jl")
end
