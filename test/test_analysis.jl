function _analysis_model(mode::Symbol)
    file = mode === :susy ? "modelMSSM0.txt" : "modelZ3_1_1.txt"
    return only(parse_orbifolder_models(read(
        joinpath(@__DIR__, "fixtures", String(mode), file), String,
    ); mode = mode))
end

function _analysis_fixture(mode::Symbol)
    directory = joinpath(@__DIR__, "fixtures", String(mode))
    detailed_file = mode === :susy ? "mssm0_detailed.txt" : "z3_1_1_detailed.txt"
    detailed = split_transcript(read(joinpath(directory, detailed_file), String))
    exact = read(joinpath(directory, "exact_gauge.txt"), String)
    gauge_end = findfirst("Simple roots:", exact).start - 1
    u1_start = findfirst("U(1) generators:", exact).start
    gauge = exact[1:gauge_end]
    roots = exact[gauge_end+1:u1_start-1]
    u1 = exact[u1_start:end]
    point, space = split(read(joinpath(directory, "space_group.txt"), String), "---SPACE---"; limit = 2)
    blocks = [
        "print summary" => output_for(detailed, "print summary"),
        "print(*) with internal information" => output_for(detailed, "print(*) with internal information"),
        "print summary of fixed points with labels" => output_for(detailed, "print summary of fixed points with labels"),
        "print gauge group" => gauge,
        "print simple roots" => roots,
        "print U1 generators" => u1,
        "print point group" => point,
        "print space group" => space,
    ]
    return join(("> $command\n$output\n" for (command, output) in blocks))
end

@testset "integrated analysis planning and parsing" begin
    requested = OrbifolderBridge._analysis_requested([
        :detailed_spectrum, :exact_gauge_data, :space_group_metadata, :localizations,
    ])
    commands = OrbifolderBridge._analysis_commands(requested)
    @test count(==("print summary"), commands) == 1
    @test count(==("print gauge group"), commands) == 1
    @test_throws ArgumentError OrbifolderBridge._analysis_requested(Symbol[])
    @test_throws ArgumentError OrbifolderBridge._analysis_requested([:spectrum, :spectrum])
    @test_throws ArgumentError OrbifolderBridge._analysis_requested([:flatness])

    for (mode, version, arity) in [(:susy, v"1.2.1", 2), (:nonsusy, v"1.0.0", 3)]
        mktempdir() do geometry
            model = _analysis_model(mode)
            geometry_file = joinpath(geometry, basename(model.space_group_file))
            write(geometry_file, "fixture Geometry identity for $mode\n")
            backend = BackendInfo(mode, version, "fixture-backend", geometry, ())
            context = ComputationContext(model, backend, VEVConfigurationRef("TestConfig1"), 30)
            output = _analysis_fixture(mode) * "> warning command\nWarning: retained fixture warning.\n"
            result = OrbifolderBridge._parse_analysis(context, requested, commands, output)

            @test result.requested == requested
            @test result.detailed_spectrum.summary == result.spectrum
            @test result.exact_gauge_data.gauge_group == result.gauge_group
            @test !isempty(result.localizations)
            @test all(length(loc.constructing_element.sector.coordinates) == arity for loc in result.localizations)
            @test result.space_group_metadata.backend == mode
            @test result.provenance.configuration == VEVConfigurationRef("TestConfig1")
            @test length(result.provenance.model_sha256) == 64
            @test length(result.provenance.geometry.sha256) == 64
            @test result.provenance.geometry.file == model.space_group_file
            @test result.provenance.warnings == ["Warning: retained fixture warning."]
            @test result.provenance.transcript == output
            @test first(result.provenance.commands) ==
                  "load orbifolds($(OrbifolderBridge._model_filename(model)))"
            @test last(result.provenance.commands) == "exit"
        end
    end
end

@testset "integrated analysis diagnostics" begin
    mktempdir() do geometry
        model = _analysis_model(:susy)
        write(joinpath(geometry, basename(model.space_group_file)), "geometry\n")
        backend = BackendInfo(:susy, v"1.2.1", "fixture-backend", geometry, ())
        context = ComputationContext(model, backend, nothing, 30)
        @test_throws ArgumentError ComputationContext(model, backend, nothing, 0)
        wrong = BackendInfo(:nonsusy, v"1.0.0", "fixture-backend", geometry, ())
        @test_throws ArgumentError ComputationContext(model, wrong, nothing, 30)

        malformed = "> print summary\nformat drift\n"
        error = try
            OrbifolderBridge._parse_analysis(
                context, [:spectrum], ["cd spectrum", "print summary", "cd .."], malformed,
            )
            nothing
        catch e
            e
        end
        @test error isa AnalysisParseError
        @test error.item == :spectrum
        @test error.transcript == malformed
    end
    @test isempty(analyze_batch(OrbifolderModel[]; include = [:spectrum]))
    @test_throws ArgumentError analyze_batch(OrbifolderModel[]; include = [:spectrum], ntasks = 0)
end

@testset "integrated analysis against real binaries (skipped if unavailable)" begin
    backends = [
        (:susy, joinpath(@__DIR__, "..", "vendor", "orbifolder", "src", "orbifolder", "orbifolder"),
         "ORBIFOLDER_BIN", "ORBIFOLDER_GEOMETRY_DIR"),
        (:nonsusy, joinpath(@__DIR__, "..", "vendor", "nonSUSYorbifolder", "nonSUSYorbifolder"),
         "NONSUSYORBIFOLDER_BIN", "NONSUSYORBIFOLDER_GEOMETRY_DIR"),
    ]
    for (mode, binary, binary_env, geometry_env) in backends
        isfile(binary) || continue
        withenv(binary_env => binary, geometry_env => nothing) do
            model = _analysis_model(mode)
            result = analyze(
                model;
                config = VEVConfigurationRef("TestConfig1"),
                include = [
                    :detailed_spectrum, :exact_gauge_data, :twist,
                    :shift_vectors, :wilson_lines, :space_group_metadata, :localizations,
                ],
            )
            @test result.provenance.backend.kind == mode
            @test result.detailed_spectrum.summary == result.spectrum
            @test result.exact_gauge_data.gauge_group == result.gauge_group
            @test !isempty(result.localizations)
            @test length(result.provenance.commands) > length(result.requested)

            batch = analyze_batch([model, model]; include = [:spectrum, :twist], ntasks = 2)
            @test length(batch) == 2
            @test getfield.(batch, :spectrum) == fill(batch[1].spectrum, 2)
        end
    end
end
