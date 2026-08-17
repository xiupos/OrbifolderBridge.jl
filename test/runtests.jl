using Test
using OrbifolderBridge

@testset "OrbifolderBridge.jl" verbose = true begin
    include("test_core.jl")
    include("test_parsers.jl")
    include("test_oscar_mapping.jl")
end
