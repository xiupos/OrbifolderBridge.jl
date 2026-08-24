const _NONSUSY_SHIFT1 = [0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0]
const _NONSUSY_SHIFT2 = [1 // 3, 1 // 3, -2 // 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

const _SUSY_SHIFT1 = [-2 // 3, 0, 0, 0, 0, 0, 2 // 3, 4 // 3, -2 // 3, -2 // 3, 0, 0, 0, 0, 1, 1]
const _SUSY_SHIFT2 =
    [2 // 3, -1, -2 // 3, -2 // 3, 0, 2 // 3, -1 // 3, 2 // 3, -2 // 3, -2 // 3, -1, 1 // 3, 2 // 3, 1, 2 // 3, 1]
const _SUSY_WL3 = [
    -5 // 6, -5 // 6, 1 // 6, 1 // 6, 1 // 2, 3 // 2, 1 // 6, -1 // 6,
    -1 // 2, 7 // 6, 1 // 2, -5 // 6, 7 // 6, -5 // 6, 5 // 6, -1 // 6,
]

@testset "OrbifolderModel constructor validation" begin
    @test_throws ArgumentError OrbifolderModel(;
        mode = :bogus, label = "M", point_group = "Z3_1_1", shift = zeros(Int, 16),
    )
    @test_throws ArgumentError OrbifolderModel(;
        mode = :susy, label = "M", point_group = "Z3_1_1", shift = zeros(Int, 16), lattice = :bogus,
    )
    @test_throws ArgumentError OrbifolderModel(;
        mode = :susy, label = "M", point_group = "Z3_1_1", shift = zeros(Int, 15),
    )
    @test_throws ArgumentError OrbifolderModel(;
        mode = :susy, label = "M", point_group = "Z3_1_1", shift = (zeros(Int, 16), zeros(Int, 15)),
    )
    @test_throws ArgumentError OrbifolderModel(;
        mode = :susy, label = "M", point_group = "Z3_1_1", shift = zeros(Int, 16),
        wilson_lines = [zeros(Int, 16) for _ in 1:7],
    )

    m = OrbifolderModel(; mode = :susy, label = "M", point_group = "Z3_1_1", shift = zeros(Int, 16))
    @test length(m.wilson_lines) == 6
    @test all(iszero, m.shift2)
    @test all(iszero, m.shift3)
end

@testset "model_file_text: format and round-trippable values" begin
    # nonSUSYorbifolder reads 3 shifts (the Witten embedding and two
    # compactification slots) plus 6 Wilson lines. SUSY orbifolder reads 2
    # shifts plus the same 6 Wilson lines.
    m_nonsusy = OrbifolderModel(;
        mode = :nonsusy, label = "Z3_1_1", point_group = "Z3_1_1",
        shift = (_NONSUSY_SHIFT1, _NONSUSY_SHIFT2),
    )
    text = model_file_text(m_nonsusy)
    data_lines = split(text, '\n')[6:14]
    @test length(data_lines) == 9
    @test data_lines[1] == "0/1 0/1 0/1 1/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 1/1 0/1 0/1 0/1 0/1"
    @test data_lines[2] == "1/3 1/3 -2/3 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1 0/1"
    @test all(l -> l == join(fill("0/1", 16), " "), data_lines[3:9])
    @test startswith(text, "begin model\nLabel:Z3_1_1\nSpaceGroup:Geometry/Geometry_Z3_1_1.txt\nLattice:E8xE8\n")
    @test endswith(text, "end model\n")

    zero16 = zeros(Rational{Int}, 16)
    m_susy = OrbifolderModel(;
        mode = :susy, label = "MSSM0", point_group = "Z3xZ3_1_1",
        shift = (_SUSY_SHIFT1, _SUSY_SHIFT2),
        wilson_lines = [zero16, zero16, _SUSY_WL3, _SUSY_WL3, zero16, zero16],
    )
    @test occursin("Lattice:E8xE8", model_file_text(m_susy))
    @test occursin("SpaceGroup:Geometry/Geometry_Z3xZ3_1_1.txt", model_file_text(m_susy))
end

@testset "compute_* against real binaries (skipped if unavailable)" begin
    nonsusy_bin = joinpath(@__DIR__, "..", "vendor", "nonSUSYorbifolder", "nonSUSYorbifolder")
    susy_bin = joinpath(@__DIR__, "..", "vendor", "orbifolder", "src", "orbifolder", "orbifolder")

    if isfile(nonsusy_bin)
        withenv("NONSUSYORBIFOLDER_BIN" => nonsusy_bin, "NONSUSYORBIFOLDER_GEOMETRY_DIR" => nothing) do
            m = OrbifolderModel(;
                mode = :nonsusy, label = "Z3_1_1", point_group = "Z3_1_1",
                shift = (_NONSUSY_SHIFT1, _NONSUSY_SHIFT2),
            )
            spec = compute_spectrum(m)
            @test spec.gauge_group.nonabelian == ["SO(10)", "SU(3)", "SO(16)"]
            @test length(spec.fields) == 13

            @test compute_gauge_group(m) == spec.gauge_group
            @test compute_twist(m).vectors == [[0 // 1, 1 // 3, 1 // 3, -2 // 3]]
            @test compute_wilson_lines(m).orders == [3, 3, 3, 3, 3, 3]
            @test length(compute_shift_vectors(m)) == 1
            detailed = compute_detailed_spectrum(m)
            @test length(detailed.fields) == sum(f.multiplicity for f in spec.fields)
            @test detailed.summary == spec
            configs = list_vev_configurations(m)
            @test getfield.(getfield.(configs, :configuration), :label) ==
                  ["StandardConfig1", "TestConfig1"]
            explicit = VEVConfigurationRef("StandardConfig1")
            @test compute_spectrum(m, explicit).gauge_group.config_label == "StandardConfig1"
            @test compute_gauge_sector(m, explicit).gauge_group.config_label == "StandardConfig1"
            spec = VEVConfigurationSpec(;
                name = "BridgeConfig1",
                observable_nonabelian = [1, 3],
                observable_u1 = Int[],
            )
            materialized = materialize_vev_configuration(m, spec)
            @test materialized.configuration.configuration.label == "BridgeConfig1"
            @test materialized.gauge_sector.observable_nonabelian == [1, 3]
            @test isempty(materialized.gauge_sector.observable_u1)
            @test isempty(materialized.assignments)
            @test isnothing(materialized.detailed_spectrum)
            @test_throws ArgumentError materialize_vev_configuration(
                m,
                VEVConfigurationSpec(;
                    name = "UnsupportedVEV1",
                    assignments = [VEVAssignment(FieldID(9), 1)],
                ),
            )
        end
    end

    if isfile(susy_bin)
        withenv("ORBIFOLDER_BIN" => susy_bin, "ORBIFOLDER_GEOMETRY_DIR" => nothing) do
            zero16 = zeros(Rational{Int}, 16)
            m = OrbifolderModel(;
                mode = :susy, label = "MSSM0", point_group = "Z3xZ3_1_1",
                shift = (_SUSY_SHIFT1, _SUSY_SHIFT2),
                wilson_lines = [zero16, zero16, _SUSY_WL3, _SUSY_WL3, zero16, zero16],
            )
            spec = compute_spectrum(m)
            @test spec.gauge_group.n_u1 == 9
            @test length(spec.fields) == 82

            wl = compute_wilson_lines(m)
            @test wl.identifications == [("W_1", "W_2"), ("W_3", "W_4"), ("W_5", "W_6")]
            @test compute_twist(m).vectors == [[0 // 1, 0 // 1, 1 // 3, -1 // 3], [0 // 1, 1 // 3, 0 // 1, -1 // 3]]
            detailed = compute_detailed_spectrum(m)
            @test length(detailed.fields) == sum(f.multiplicity for f in spec.fields)
            @test detailed.summary == spec
            configs = list_vev_configurations(m)
            @test getfield.(getfield.(configs, :configuration), :label) ==
                  ["StandardConfig1", "TestConfig1"]
            explicit = VEVConfigurationRef("StandardConfig1")
            @test compute_gauge_group(m, explicit).config_label == "StandardConfig1"
            @test compute_detailed_spectrum(m, explicit).summary.gauge_group.config_label ==
                  "StandardConfig1"
            spec = VEVConfigurationSpec(;
                name = "BridgeConfig1",
                assignments = [VEVAssignment(FieldID(11), 1)],
            )
            materialized = materialize_vev_configuration(m, spec)
            @test materialized.configuration.fields_with_vev == ["F_1"]
            @test materialized.assignments == [FieldVEV(FieldID(11), "F_1", 1.0)]
            @test materialized.spectrum.gauge_group.config_label == "BridgeConfig1"
            @test materialized.gauge_sector.hidden_u1 == collect(2:9)
        end
    end
end
