using Oscar

function exact_gauge_fixture(mode)
    text = read(joinpath(@__DIR__, "fixtures", String(mode), "exact_gauge.txt"), String)
    gauge_end = findfirst("Simple roots:", text).start - 1
    roots_start = gauge_end + 1
    u1_start = findfirst("U(1) generators:", text).start
    return (
        text[1:gauge_end],
        text[roots_start:u1_start-1],
        text[u1_start:end],
    )
end

@testset "parse exact gauge data" begin
    gauge, roots, u1 = exact_gauge_fixture(:nonsusy)
    data = parse_exact_gauge_data(
        gauge,
        roots,
        u1;
        spectrum_output = "First U(1) is anomalous with tr Q_anom = 21000.00.",
    )
    @test data.gauge_group.nonabelian == ["SO(10)", "SU(3)", "SO(16)"]
    @test length.(getfield.(data.factors, :simple_roots)) == [5, 2, 8]
    @test length(data.u1_generators) == 1
    @test data.u1_generators[1][1:3] == [24, 24, 24]
    @test data.anomalous_u1 == 1
    @test data.anomalous_tr_q == 21000.0
    @test data.observable_nonabelian == [1, 2, 3]
    @test isempty(data.hidden_nonabelian)

    gauge, roots, u1 = exact_gauge_fixture(:susy)
    hidden = parse_exact_gauge_data(gauge, roots, u1)
    @test hidden.observable_nonabelian == [1, 2]
    @test hidden.hidden_nonabelian == [3, 4, 5]
    @test hidden.observable_u1 == [1]
    @test hidden.hidden_u1 == [2]
    @test hidden.anomalous_u1 === nothing
    @test hidden.anomalous_tr_q === nothing

    @test_throws ErrorException parse_exact_gauge_data(
        gauge,
        "Simple roots:\n  (1,0), (0,0)",
        u1,
    )
    @test_throws ErrorException parse_exact_gauge_data(gauge, roots, "no generators")
end

@testset "exact gauge OSCAR matrices" begin
    gauge, roots, u1 = exact_gauge_fixture(:nonsusy)
    data = parse_exact_gauge_data(gauge, roots, u1)
    root_matrix = simple_root_matrix(data.factors[1])
    @test base_ring(root_matrix) == QQ
    @test size(root_matrix) == (5, 16)
    generators = u1_generator_matrix(data)
    @test size(generators) == (1, 16)
    @test u1_gram_matrix(data)[1, 1] == 3 * 24^2
    normalization = u1_normalization(data)
    @test normalization.gram == u1_gram_matrix(data)
    @test normalization.dual_gram * normalization.gram == identity_matrix(QQ, 1)
    @test normalization.squared_norms == [QQ(3 * 24^2)]
    @test normalization.orthogonal

    duplicate = ExactGaugeData(
        GaugeGroup("Bad1", String[], 2),
        GaugeFactorEmbedding[],
        [data.u1_generators[1], data.u1_generators[1]],
        nothing,
        nothing,
        Int[],
        Int[],
        [1, 2],
        Int[],
    )
    @test_throws ErrorException u1_normalization(duplicate)
end

@testset "embedded OSCAR gauge factors" begin
    for mode in (:nonsusy, :susy)
        gauge, roots, u1 = exact_gauge_fixture(mode)
        data = parse_exact_gauge_data(gauge, roots, u1)
        factors = embedded_gauge_factors(data)
        @test length(factors) == length(data.factors)
        for factor in factors
            roots = simple_root_matrix(factor.source)
            expected = cartan_matrix(algebra_to_cartan_type(factor.source.algebra)...)
            @test gram_matrix(factor.root_lattice) == expected
            @test basis_matrix(factor.root_lattice) == roots
            weights = fundamental_weight_matrix(factor)
            @test weights * transpose(roots) == identity_matrix(QQ, size(roots, 1))

            first_weight = fundamental_weight(factor.root_system, 1)
            @test embed_weight(factor, first_weight) == weights[1:1, :]
        end
    end

    gauge, roots, u1 = exact_gauge_fixture(:nonsusy)
    data = parse_exact_gauge_data(gauge, roots, u1)
    bad = GaugeFactorEmbedding(
        1,
        "SO(10)",
        [copy(root) for root in data.factors[1].simple_roots],
    )
    bad.simple_roots[1][1] = 1
    @test_throws ErrorException embedded_gauge_factor(bad)

    factors = embedded_gauge_factors(data)
    foreign_weight = fundamental_weight(root_system(:A, 2), 1)
    @test_throws ArgumentError embed_weight(factors[1], foreign_weight)
end

function comparison_data(label, roots, u1s)
    factor = GaugeFactorEmbedding(1, "SU(3)", roots)
    group = GaugeGroup(label, ["SU(3)"], length(u1s))
    return ExactGaugeData(
        group,
        [factor],
        u1s,
        nothing,
        nothing,
        [1],
        Int[],
        collect(eachindex(u1s)),
        Int[],
    )
end

@testset "exact gauge embedding comparison" begin
    root1 = Rational{Int}[1, -1, zeros(Int, 14)...]
    root2 = Rational{Int}[0, 1, -1, zeros(Int, 13)...]
    u1a = Rational{Int}[zeros(Int, 3)..., 1, zeros(Int, 12)...]
    u1b = Rational{Int}[zeros(Int, 4)..., 1, zeros(Int, 11)...]
    u1c = Rational{Int}[zeros(Int, 5)..., 1, zeros(Int, 10)...]
    before = comparison_data("Before1", [root1, root2], [u1a, u1b])
    after = comparison_data("After1", [root1 + root2, root2], [2u1a, u1c])

    comparison = compare_gauge_embeddings(before, after)
    @test comparison.shared_simple_roots == [((1, 2), (1, 2))]
    @test comparison.before_roots_in_after_span == [(1, 1), (1, 2)]
    @test comparison.after_roots_in_before_span == [(1, 1), (1, 2)]
    @test comparison.nonabelian_intersection_rank == 2
    @test comparison.before_u1_in_after_span == [1]
    @test comparison.after_u1_in_before_span == [1]
    @test comparison.u1_intersection_rank == 1

    no_u1_before = comparison_data("Before1", [root1, root2], Vector{Rational{Int}}[])
    no_u1_after = comparison_data("After1", [root2], Vector{Rational{Int}}[])
    comparison = compare_gauge_embeddings(no_u1_before, no_u1_after)
    @test comparison.nonabelian_intersection_rank == 1
    @test comparison.u1_intersection_rank == 0
    @test isempty(comparison.before_u1_in_after_span)
end

@testset "representation resolution provenance" begin
    gauge, roots, u1 = exact_gauge_fixture(:nonsusy)
    factors = embedded_gauge_factors(parse_exact_gauge_data(gauge, roots, u1))

    exact = representation_from_dynkin_labels(
        factors[2],
        [1, 0];
        reported_dimension = 3,
    )
    @test exact.source == :exact_dynkin
    @test exact.factor_index == 2
    @test dim_of_simple_module(factors[2].root_system, exact.weight) == 3
    @test_throws ArgumentError representation_from_dynkin_labels(
        factors[2], [1, 0]; reported_dimension = 8,
    )
    @test_throws ArgumentError representation_from_dynkin_labels(factors[2], [1])
    @test_throws ArgumentError representation_from_dynkin_labels(factors[2], [-1, 0])

    fallback = resolve_representation(factors[2], -3)
    @test fallback.source == :dimension_fallback
    @test fallback.reported_dimension == -3
    @test dim_of_simple_module(factors[2].root_system, fallback.weight) == 3

    # factors[3] is SO(16) = D_8, whose 128/128' half-spin pair is two
    # distinct self-dual representations of equal dimension. Upstream's sign
    # picks between them, so dimension fallback must follow that convention
    # rather than rejecting the pair as ambiguous, and must agree with
    # `representation_weight`.
    spin_pos = resolve_representation(factors[3], 128)
    spin_neg = resolve_representation(factors[3], -128)
    @test spin_pos.source == :dimension_fallback
    @test spin_neg.source == :dimension_fallback
    @test spin_pos.weight == fundamental_weight(factors[3].root_system, 8)
    @test spin_neg.weight == fundamental_weight(factors[3].root_system, 7)
    @test spin_pos.weight != spin_neg.weight
    @test dim_of_simple_module(factors[3].root_system, spin_neg.weight) == 128

    # D_4's triality triple is genuinely irrecoverable from a bare dimension
    # (8_v, 8_s and 8_c are three mutually non-conjugate families, and
    # upstream prints all three as a plain positive 8), so the ambiguity
    # rejection must still fire there.
    d4_roots = [
        Rational{Int}[1, -1, 0, 0, zeros(Int, 12)...],
        Rational{Int}[0, 1, -1, 0, zeros(Int, 12)...],
        Rational{Int}[0, 0, 1, -1, zeros(Int, 12)...],
        Rational{Int}[0, 0, 1, 1, zeros(Int, 12)...],
    ]
    d4 = embedded_gauge_factor(GaugeFactorEmbedding(1, "SO(8)", d4_roots))
    @test_throws ErrorException resolve_representation(d4, 8)
    @test_throws ErrorException resolve_representation(d4, -8)
    @test dim_of_simple_module(d4.root_system, resolve_representation(d4, 28).weight) == 28

    field = SpectrumField(1, [10, 3, 1], :s, Rational{Int}[])
    resolved = resolve_field_representations(factors, field)
    @test all(result -> result.source == :dimension_fallback, resolved)
    exact_resolved = resolve_field_representations(
        factors,
        field;
        dynkin_labels = [[1, 0, 0, 0, 0], [1, 0], zeros(Int, 8)],
    )
    @test all(result -> result.source == :exact_dynkin, exact_resolved)
    @test_throws ArgumentError resolve_field_representations(
        factors,
        field;
        dynkin_labels = [[1, 0]],
    )
end
