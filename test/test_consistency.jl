const _CONSISTENCY_FIXTURES = joinpath(@__DIR__, "fixtures", "consistency")

_fixture(name) = read(joinpath(_CONSISTENCY_FIXTURES, name), String)

function _test_model(label; mode = :susy)
    return OrbifolderModel(;
        mode = mode, label = label, point_group = "Z3_1_1", shift = zeros(Int, 16),
    )
end

@testset "consistency transcript classification" begin
    susy = read(joinpath(@__DIR__, "fixtures", "susy", "mssm0_summary.txt"), String)
    nonsusy = read(joinpath(@__DIR__, "fixtures", "nonsusy", "z3_1_1_summary.txt"), String)
    @test OrbifolderBridge._consistency_from_transcript(susy).valid
    @test OrbifolderBridge._consistency_from_transcript(nonsusy).valid
    @test ConsistencyResult(true, "ok", susy) == ConsistencyResult(true, "ok", susy)

    rejected = OrbifolderBridge._consistency_from_transcript(
        _fixture("modular_invariance_rejection.txt"),
    )
    @test !rejected.valid
    @test occursin("modular invariance", rejected.message)
    @test rejected.output == _fixture("modular_invariance_rejection.txt")

    not_loaded = OrbifolderBridge._consistency_from_transcript(
        _fixture("label_not_loaded.txt"),
    )
    @test !not_loaded.valid
    @test occursin("label", not_loaded.message)
    @test_throws ErrorException OrbifolderBridge._consistency_from_transcript(
        _fixture("missing_shift.txt"),
    )
    @test_throws ErrorException OrbifolderBridge._consistency_from_transcript("not a transcript")

    for line in eachline(joinpath(_CONSISTENCY_FIXTURES, "rejection_messages.txt"))
        expected, diagnostic = split(line, '|'; limit = 2)
        @test OrbifolderBridge._rejection_reason(diagnostic) == expected
    end
end

@testset "consistency exception boundary" begin
    model = _test_model("M")
    timeout_runner(args...; kwargs...) = throw(OrbifolderTimeoutError(0.1))
    @test_throws OrbifolderTimeoutError OrbifolderBridge._check_consistency(model, timeout_runner)

    infrastructure_runner(args...; kwargs...) =
        throw(OrbifolderProcessError("crashed", 1, "", "segmentation fault"))
    @test_throws OrbifolderProcessError OrbifolderBridge._check_consistency(
        model, infrastructure_runner,
    )

    rejection_runner(args...; kwargs...) = throw(OrbifolderProcessError(
        "backend rejected model", 1, _fixture("modular_invariance_rejection.txt"), "",
    ))
    @test !OrbifolderBridge._check_consistency(model, rejection_runner).valid
end

@testset "consistency batch order and isolation" begin
    models = [_test_model("A"), _test_model("Bad"), _test_model("C")]
    function checker(model; timeout = 120)
        sleep(model.label == "A" ? 0.03 : 0.0)
        return ConsistencyResult(model.label != "Bad", model.label, "raw " * model.label)
    end
    results = OrbifolderBridge._check_consistency_batch(models, checker; ntasks = 3)
    @test [r.message for r in results] == ["A", "Bad", "C"]
    @test [r.valid for r in results] == [true, false, true]
    @test all(r -> r.valid == (r.message != "Bad"), results)
    @test_throws ArgumentError check_consistency_batch(models; ntasks = 0)
end

@testset "consistency against real binaries (skipped if unavailable)" begin
    nonsusy_bin = joinpath(@__DIR__, "..", "vendor", "nonSUSYorbifolder", "nonSUSYorbifolder")
    if isfile(nonsusy_bin)
        withenv("NONSUSYORBIFOLDER_BIN" => nonsusy_bin, "NONSUSYORBIFOLDER_GEOMETRY_DIR" => nothing) do
            model = OrbifolderModel(;
                mode = :nonsusy, label = "Z3_1_1", point_group = "Z3_1_1",
                shift = (_NONSUSY_SHIFT1, _NONSUSY_SHIFT2),
            )
            result = check_consistency(model)
            @test result.valid
            @test OrbifolderBridge.is_consistent(model) == result.valid
        end
    end

    susy_bin = joinpath(@__DIR__, "..", "vendor", "orbifolder", "src", "orbifolder", "orbifolder")
    if isfile(susy_bin)
        withenv("ORBIFOLDER_BIN" => susy_bin, "ORBIFOLDER_GEOMETRY_DIR" => nothing) do
            zero16 = zeros(Rational{Int}, 16)
            model = OrbifolderModel(;
                mode = :susy, label = "MSSM0", point_group = "Z3xZ3_1_1",
                shift = (_SUSY_SHIFT1, _SUSY_SHIFT2),
                wilson_lines = [zero16, zero16, _SUSY_WL3, _SUSY_WL3, zero16, zero16],
            )
            @test check_consistency(model).valid
        end
    end
end
