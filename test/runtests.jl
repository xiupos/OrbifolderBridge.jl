using Test
using OrbifolderBridge

@testset "OrbifolderBridge.jl" verbose = true begin
    include("test_core.jl")
    include("test_parsers.jl")
end
