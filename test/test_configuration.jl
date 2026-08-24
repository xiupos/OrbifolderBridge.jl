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
    @test_throws ErrorException parse_vev_configurations("no table")
    @test_throws ErrorException parse_vev_configurations(replace(
        read(_configuration_fixture("nonsusy", "vev_configs.txt"), String),
        "->" => "  ",
    ))
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
