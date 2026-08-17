using Oscar

@testset "algebra_to_cartan_type" begin
    @test algebra_to_cartan_type("SU(2)") == (:A, 1)
    @test algebra_to_cartan_type("SU(3)") == (:A, 2)
    @test algebra_to_cartan_type("SO(10)") == (:D, 5)
    @test algebra_to_cartan_type("SO(16)") == (:D, 8)
    @test algebra_to_cartan_type("SO(32)") == (:D, 16)
    @test algebra_to_cartan_type("E_6") == (:E, 6)
    @test algebra_to_cartan_type("E_7") == (:E, 7)
    @test algebra_to_cartan_type("E_8") == (:E, 8)
    @test algebra_to_cartan_type("E8") == (:E, 8) # tolerate the underscore-less spelling too
    @test algebra_to_cartan_type("SO(5)") == (:B, 2) # not emitted by upstream, but parses mechanically
    @test algebra_to_cartan_type("Sp(4)") == (:C, 2)

    @test_throws ErrorException algebra_to_cartan_type("SO(4)")
    @test_throws ErrorException algebra_to_cartan_type("SU(1)")
    @test_throws ErrorException algebra_to_cartan_type("E_9")
    @test_throws ErrorException algebra_to_cartan_type("nonsense")
end

@testset "find_weight_of_dimension / dual_weight" begin
    A2 = root_system(:A, 2)
    @test dim_of_simple_module(A2, find_weight_of_dimension(A2, 1)) == 1
    @test find_weight_of_dimension(A2, 3) == fundamental_weight(A2, 1)
    @test dim_of_simple_module(A2, find_weight_of_dimension(A2, 8)) == 8 # adjoint

    w1 = fundamental_weight(A2, 1)
    w2 = fundamental_weight(A2, 2)
    @test dual_weight(A2, w1) == w2
    @test dual_weight(A2, w2) == w1

    D5 = root_system(:D, 5)
    @test dim_of_simple_module(D5, find_weight_of_dimension(D5, 10)) == 10   # vector
    @test dim_of_simple_module(D5, find_weight_of_dimension(D5, 16)) == 16   # spinor

    D8 = root_system(:D, 8)
    @test dim_of_simple_module(D8, find_weight_of_dimension(D8, 128)) == 128 # spinor

    @test_throws ErrorException find_weight_of_dimension(A2, 999999)
    @test_throws ArgumentError find_weight_of_dimension(A2, 0)
end

@testset "representation_weight" begin
    A2 = root_system(:A, 2)
    @test representation_weight(A2, 3) == fundamental_weight(A2, 1)
    @test representation_weight(A2, -3) == fundamental_weight(A2, 2)
    @test representation_weight(A2, 1) == WeightLatticeElem(A2, [0, 0])
end

@testset "gauge_group_root_systems / field_weights against fixtures" begin
    pairs = split_transcript(read(joinpath(@__DIR__, "fixtures", "nonsusy", "z3_1_1_summary.txt"), String))
    spec = parse_spectrum(output_for(pairs, "print summary"))
    Rs = gauge_group_root_systems(spec.gauge_group)
    @test length(Rs) == 3

    for field in spec.fields
        ws = field_weights(Rs, field)
        @test length(ws) == length(field.rep)
        for (R, w, rep) in zip(Rs, ws, field.rep)
            @test dim_of_simple_module(R, w) == abs(rep)
        end
    end

    mismatched = SpectrumField(1, [1, 1], :s, Rational{Int}[])
    @test_throws ArgumentError field_weights(Rs, mismatched)
end
