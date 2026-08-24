_configuration_fixture(parts...) = joinpath(@__DIR__, "fixtures", parts...)

@testset "VEV configuration references and tables" begin
    standard = VEVConfigurationRef("StandardConfig1")
    @test standard.label == "StandardConfig1"
    @test VEVConfigurationRef("SMConfig2") == VEVConfigurationRef("SMConfig2")
    @test_throws ArgumentError VEVConfigurationRef("StandardConfig")
    @test_throws ArgumentError VEVConfigurationRef("Test1)\nexit")

    for mode in ("susy", "nonsusy")
        text = read(_configuration_fixture(mode, "vev_configs.txt"), String)
        configs = parse_vev_configurations(text)
        @test getfield.(getfield.(configs, :configuration), :label) ==
              ["StandardConfig1", "TestConfig1"]
        @test findall(c -> c.selected, configs) == [2]
        @test all(c -> c.active_label == 1 && c.label_count == 1, configs)
        @test all(c -> isempty(c.fields_with_vev), configs)
    end

    with_vevs = replace(
        read(_configuration_fixture("susy", "vev_configs.txt"), String),
        "-> \"TestConfig1\"     |        1 /  1 |" =>
            "-> \"TestConfig1\"     |        1 /  2 | F_1 F_7",
    )
    selected = only(filter(c -> c.selected, parse_vev_configurations(with_vevs)))
    @test selected.label_count == 2
    @test selected.fields_with_vev == ["F_1", "F_7"]

    assignment_text = read(_configuration_fixture("susy", "vev_assignment.txt"), String)
    assigned_config = only(filter(
        c -> c.selected,
        parse_vev_configurations(output_for(split_transcript(assignment_text), "print configs")),
    ))
    @test assigned_config.fields_with_vev == ["F_1"]
    continued = replace(
        assignment_text,
        "<F_1>" => "<F_1> <F_2> <F_3> <F_4> <F_5> <F_6> <F_7> <F_8> <F_9> <F_10>\n" *
                   "                         |               | <F_11> <F_12>",
    )
    continued_config = only(filter(
        c -> c.selected,
        parse_vev_configurations(output_for(split_transcript(continued), "print configs")),
    ))
    @test continued_config.fields_with_vev == ["F_$i" for i in 1:12]
    @test_throws ErrorException parse_vev_configurations("no table")
    @test_throws ErrorException parse_vev_configurations(replace(
        read(_configuration_fixture("nonsusy", "vev_configs.txt"), String),
        "->" => "  ",
    ))
end

@testset "declarative VEV configuration specifications" begin
    assignment = VEVAssignment(FieldID(11), 1)
    @test assignment.value === 1.0
    @test_throws ArgumentError VEVAssignment(FieldID(11), Inf)

    spec = VEVConfigurationSpec(;
        name = "BridgeConfig1",
        base = VEVConfigurationRef("TestConfig1"),
        observable_nonabelian = [1, 2],
        observable_u1 = Int[],
        assignments = [assignment],
    )
    @test spec.recompute_unbroken_group
    @test OrbifolderBridge._observable_sector_command(spec) ==
          "select observable sector: gauge group(1,2) no U1s"
    @test_throws ArgumentError VEVConfigurationSpec(
        name = "Bad1", observable_nonabelian = [1, 1],
    )
    @test_throws ArgumentError VEVConfigurationSpec(
        name = "Bad1", observable_u1 = [0],
    )
    @test_throws ArgumentError VEVConfigurationSpec(
        name = "Bad1", assignments = [assignment, assignment],
    )

    preserve = VEVConfigurationSpec(name = "Preserve1")
    @test isnothing(OrbifolderBridge._observable_sector_command(preserve))
    @test !preserve.recompute_unbroken_group

    output = read(_configuration_fixture("susy", "vev_assignment.txt"), String)
    vevs = parse_field_vevs(output_for(
        split_transcript(output), "print(F_1) with internal information",
    ))
    @test vevs == [FieldVEV(FieldID(11), "F_1", 1.0)]
    @test isempty(parse_field_vevs(replace(
        output_for(split_transcript(output), "print(F_1) with internal information"),
        r"(?m)^\s*vev\s*:.*$" => "",
    )))
end

@testset "observable and hidden gauge sectors" begin
    sector = parse_gauge_sector("""
      Gauge group in vev-configuration "SMConfig1": SU(3)_C x SU(2)_L x [SU(2)] and [SU(3)] and [U(1)_1] x U(1)_2,Y x [U(1)_3]
    """)
    @test sector.gauge_group == GaugeGroup(
        "SMConfig1", ["SU(3)_C", "SU(2)_L", "SU(2)", "SU(3)"], 3,
    )
    @test sector.observable_nonabelian == [1, 2]
    @test sector.hidden_nonabelian == [3, 4]
    @test sector.observable_u1 == [2]
    @test sector.hidden_u1 == [1, 3]

    all_observable = parse_gauge_sector("""
      Gauge group in vev-configuration "TestConfig1": SO(10) x SU(3) and SO(16) and U(1)_1
    """)
    @test all_observable.observable_nonabelian == [1, 2, 3]
    @test isempty(all_observable.hidden_nonabelian)
    @test all_observable.observable_u1 == [1]
end

@testset "configuration command rendering and diagnostics" begin
    config = VEVConfigurationRef("StandardConfig1")
    @test OrbifolderBridge._configuration_commands(
        config, ["cd spectrum", "print summary"],
    ) == [
        "cd vev-config", "use config(StandardConfig1)", "cd ..",
        "cd spectrum", "print summary",
    ]
    @test isnothing(OrbifolderBridge._validate_configuration_selection(
        "Now using vev-configuration \"StandardConfig1\".", config,
    ))
    err = try
        OrbifolderBridge._validate_configuration_selection(
            "Vev-configuration \"Missing1\" not known.", VEVConfigurationRef("Missing1"),
        )
        nothing
    catch e
        e
    end
    @test err isa VEVConfigurationError
    @test occursin("not known", err.transcript)
end
