_generation_fixture(parts...) = joinpath(@__DIR__, "fixtures", parts...)

@testset "upstream model-file parser" begin
    generated = read(_generation_fixture("nonsusy", "generated_model.txt"), String)
    models = parse_orbifolder_models(generated; mode = :nonsusy)
    @test length(models) == 1
    @test models[1].label == "Random1"
    @test models[1].space_group_file == "Geometry/Geometry_Z3_1_1.txt"
    @test models[1].shift2[1:3] == [1 // 3, 1 // 3, -2 // 3]
    @test length(models[1].wilson_lines) == 6
    @test all(w -> all(iszero, w), models[1].wilson_lines)

    two = parse_orbifolder_models(generated * "\n" * replace(generated, "Random1" => "Random2"); mode = :nonsusy)
    @test getfield.(two, :label) == ["Random1", "Random2"]
    @test parse_orbifolder_models(model_file_text(models[1]); mode = :nonsusy) == models

    err = try
        parse_orbifolder_models(replace(generated, "end model" => ""); mode = :nonsusy)
        nothing
    catch e
        e
    end
    @test err isa UpstreamModelParseError
    @test err.text == replace(generated, "end model" => "")

    nonzero_extra = replace(
        generated,
        "end model" => "1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0\nend model",
    )
    @test_throws UpstreamModelParseError parse_orbifolder_models(nonzero_extra; mode = :nonsusy)
end

@testset "classification and anomaly fixture parsers" begin
    backend = BackendInfo(:susy, v"1.2.1", "orbifolder", "Geometry", ())
    sm_text = read(_generation_fixture("susy", "classification_sm.txt"), String)
    sm = OrbifolderBridge._classification_from_output(sm_text, 3, backend)
    @test sm.classes == [:sm]
    @test sm.configurations == Dict(:sm => ["SMConfig1"])
    @test sm.generations == 3

    none_text = read(_generation_fixture("nonsusy", "classification_none.txt"), String)
    none = OrbifolderBridge._classification_from_output(none_text, 3, backend)
    @test isempty(none.classes)
    @test isempty(none.configurations)

    anomaly = read(_generation_fixture("nonsusy", "anomaly_universal.txt"), String)
    @test OrbifolderBridge._anomaly_report_from_output(anomaly, backend).universal
    nonuniversal = read(_generation_fixture("susy", "anomaly_nonuniversal.txt"), String)
    @test !OrbifolderBridge._anomaly_report_from_output(nonuniversal, backend).universal
    @test_throws ErrorException OrbifolderBridge._anomaly_report_from_output(
        "unexpected",
        backend,
    )
end

@testset "model-generation requests and commands" begin
    request = ModelGenerationRequest(;
        count = 4,
        inherit = (true, true, true, true, true, true, true, false),
        classes = [:sm, :pati_salam],
        generations = 3,
        inequivalent = true,
        compare_couplings_through = 4,
        check_anomalies = false,
    )
    @test request.count == 4
    @test request.inequivalent
    @test request.classes == [:sm, :pati_salam]

    model = only(parse_orbifolder_models(
        read(_generation_fixture("susy", "modelMSSM0.txt"), String);
        mode = :susy,
    ))
    command = OrbifolderBridge._generation_command(model, request, "generated.txt")
    @test command == "create random orbifold from(MSSM0) if(SM PS inequivalent 3generations) " *
                     "save to(generated.txt) #models(4) use(1,1,1,1,1,1,1,0) " *
                     "do not check anomalies compare #couplings of order(4)"

    @test_throws ArgumentError ModelGenerationRequest(count = 0)
    @test_throws ArgumentError ModelGenerationRequest(inherit = ntuple(_ -> true, 8))
    @test_throws ArgumentError ModelGenerationRequest(classes = [:bogus])
    @test_throws ArgumentError ModelGenerationRequest(generations = 3)
    @test_throws ArgumentError ModelGenerationRequest(compare_couplings_through = 2)

    sanitized = OrbifolderBridge._sanitized_generation_transcript("child PID 123 and PID 456")
    @test sanitized == "child PID <redacted> and PID <redacted>"
    @test OrbifolderBridge._reported_diagnostics(
        "Warning: bad\nCannot continue\nModels created without problems.\nall good",
    ) ==
          [
              GenerationDiagnostic(:warning, "Warning: bad"),
              GenerationDiagnostic(:rejection, "Cannot continue"),
          ]
end

@testset "published upstream generation examples" begin
    z2xz4 = only(parse_orbifolder_models(
        read(_generation_fixture("nonsusy", "modelZ2xZ4_1_6.txt"), String);
        mode = :nonsusy,
    ))
    sm_request = ModelGenerationRequest(;
        count = 3,
        inherit = ntuple(_ -> false, 8),
        classes = [:sm],
        inequivalent = true,
    )
    @test OrbifolderBridge._generation_command(z2xz4, sm_request, "models.txt") ==
          "create random orbifold from(Z2xZ4_1_6) if(SM inequivalent) " *
          "save to(models.txt) #models(3) use(0,0,0,0,0,0,0,0)"

    z3 = only(parse_orbifolder_models(
        read(_generation_fixture("nonsusy", "modelZ3_1_1.txt"), String);
        mode = :nonsusy,
    ))
    su5_request = ModelGenerationRequest(;
        count = 3,
        inherit = ntuple(_ -> false, 8),
        classes = [:su5],
        inequivalent = true,
    )
    @test OrbifolderBridge._generation_command(z3, su5_request, "modelsSU5.txt") ==
          "create random orbifold from(Z3_1_1) if(SU5 inequivalent) " *
          "save to(modelsSU5.txt) #models(3) use(0,0,0,0,0,0,0,0)"

    susy_source = only(parse_orbifolder_models(
        read(_generation_fixture("susy", "modelMSSM0.txt"), String);
        mode = :susy,
    ))
    z3_standard_embedding = ModelGenerationRequest(;
        count = 10,
        inherit = (true, true, false, false, false, false, false, false),
        inequivalent = true,
    )
    @test occursin(
        "if(inequivalent) save to(models.txt) #models(10) use(1,1,0,0,0,0,0,0)",
        OrbifolderBridge._generation_command(susy_source, z3_standard_embedding, "models.txt"),
    )

    z6ii_mssm = ModelGenerationRequest(;
        count = 10,
        inherit = (true, true, true, true, true, true, false, false),
        classes = [:sm],
        inequivalent = true,
    )
    @test occursin(
        "if(SM inequivalent) save to(models.txt) #models(10) use(1,1,1,1,1,1,0,0)",
        OrbifolderBridge._generation_command(susy_source, z6ii_mssm, "models.txt"),
    )
end
