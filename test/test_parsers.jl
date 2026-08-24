@testset "parse_rational / parse_rational_vector" begin
    @test parse_rational("1/3") == 1 // 3
    @test parse_rational("-2/3") == -2 // 3
    @test parse_rational("0") == 0
    @test parse_rational(" 5 ") == 5
    @test parse_rational_vector("1/3, -2/3, 0") == [1 // 3, -2 // 3, 0 // 1]
    @test parse_rational_vector("") == Rational{Int}[]
end

@testset "split_transcript" begin
    text = read(joinpath(@__DIR__, "fixtures", "nonsusy", "z3_1_1_summary.txt"), String)
    pairs = split_transcript(text)
    cmds = first.(pairs)
    @test cmds == [
        "load orbifolds(modelZ3_1_1.txt)",
        "cd Z3_1_1",
        "cd spectrum",
        "print summary",
        "cd ..",
        "cd model",
        "print twist",
        "print shift",
        "print Wilson lines",
        "cd ..",
        "cd gauge group",
        "print gauge group",
    ]
    @test occursin("Gauge group in vev-configuration", output_for(pairs, "print summary"))
    @test_throws ErrorException output_for(pairs, "does not exist")

    # susy transcripts have a banner and a leading "/" root prompt; both must
    # still split cleanly, and blank-command lines (banner echoes) are dropped.
    susy_text = read(joinpath(@__DIR__, "fixtures", "susy", "mssm0_summary.txt"), String)
    susy_pairs = split_transcript(susy_text)
    @test all(!isempty(cmd) for (cmd, _) in susy_pairs)
    @test ("print summary" in first.(susy_pairs))
end

@testset "parse_gauge_group" begin
    gg = parse_gauge_group(
        "Gauge group in vev-configuration \"TestConfig1\": SO(10) x SU(3) and SO(16) and U(1)",
    )
    @test gg.config_label == "TestConfig1"
    @test gg.nonabelian == ["SO(10)", "SU(3)", "SO(16)"]
    @test gg.n_u1 == 1

    gg2 = parse_gauge_group(
        "Gauge group in vev-configuration \"TestConfig1\": SU(3) x SU(2) and SU(3) x SU(2) x SU(2) and U(1)^9",
    )
    @test gg2.nonabelian == ["SU(3)", "SU(2)", "SU(3)", "SU(2)", "SU(2)"]
    @test gg2.n_u1 == 9

    gg3 = parse_gauge_group(
        "Gauge group in vev-configuration \"TestConfig1\": SU(3) and U(1)_1 x U(1)_2 x U(1)_3",
    )
    @test gg3.nonabelian == ["SU(3)"]
    @test gg3.n_u1 == 3
end

@testset "parse_spectrum against fixtures" begin
    for (file, expected_config, expected_nonabelian, expected_n_u1, expected_tr_q, expected_n_fields) in [
        (
            joinpath(@__DIR__, "fixtures", "nonsusy", "z3_1_1_summary.txt"),
            "TestConfig1",
            ["SO(10)", "SU(3)", "SO(16)"],
            1,
            21000.0,
            13,
        ),
        (
            joinpath(@__DIR__, "fixtures", "susy", "mssm0_summary.txt"),
            "TestConfig1",
            ["SU(3)", "SU(2)", "SU(3)", "SU(2)", "SU(2)"],
            9,
            960.0,
            82,
        ),
    ]
        pairs = split_transcript(read(file, String))
        spec = parse_spectrum(output_for(pairs, "print summary"))
        @test spec.gauge_group.config_label == expected_config
        @test spec.gauge_group.nonabelian == expected_nonabelian
        @test spec.gauge_group.n_u1 == expected_n_u1
        @test spec.anomalous_tr_q == expected_tr_q
        @test length(spec.fields) == expected_n_fields
        @test all(length(f.rep) == length(expected_nonabelian) for f in spec.fields)
        @test all(length(f.charges) == expected_n_u1 for f in spec.fields)
    end

    pairs = split_transcript(read(joinpath(@__DIR__, "fixtures", "nonsusy", "z3_1_1_summary.txt"), String))
    spec = parse_spectrum(output_for(pairs, "print summary"))
    f1 = spec.fields[1]
    @test f1.multiplicity == 3
    @test f1.rep == [10, 3, 1]
    @test f1.statistic == :s
    @test f1.charges == [-24 // 1]
    @test spec.fields[end].statistic == :f
end

@testset "parse_detailed_spectrum and field queries" begin
    @test_throws ErrorException OrbifolderBridge._parse_field_details("no fields")
    cases = [
        ("nonsusy", "z3_1_1_detailed.txt", 205, 1, "s_1", FieldID(6), Sector([0, 0, 0])),
        ("susy", "mssm0_detailed.txt", 254, 9, "F_1", FieldID(11), Sector([0, 0])),
    ]
    for (mode, file, count, n_u1, first_label, first_id, first_sector) in cases
        pairs = split_transcript(read(joinpath(@__DIR__, "fixtures", mode, file), String))
        detailed = parse_detailed_spectrum(
            output_for(pairs, "print summary"),
            output_for(pairs, "print(*) with internal information"),
            output_for(pairs, "print summary of fixed points with labels"),
        )
        @test length(detailed.fields) == count == sum(f.multiplicity for f in detailed.summary.fields)
        @test detailed.summary.gauge_group.n_u1 == n_u1
        @test length(unique(f.id for f in detailed.fields)) == count
        @test length(unique(f.label for f in detailed.fields)) == count
        @test all(f.localization !== nothing for f in detailed.fields)
        @test all(f.localization.translation == f.constructing_translation for f in detailed.fields)
        @test all(length(f.localization.local_shift) == 16 for f in detailed.fields)

        first_field = only(find_fields(detailed; label = first_label))
        @test first_field.id == first_id
        @test first_field.sector == first_sector
        @test only(find_fields(detailed; representation = first_field.rep, charges = first_field.charges,
            sector = first_sector, label = first_label)) == first_field
        @test first_field in find_fields(detailed; charge = 1 => first_field.charges[1])
        @test isempty(find_fields(detailed; label = "not_a_field"))
    end

    susy_pairs = split_transcript(read(joinpath(@__DIR__, "fixtures", "susy", "mssm0_detailed.txt"), String))
    susy = parse_detailed_spectrum(
        output_for(susy_pairs, "print summary"),
        output_for(susy_pairs, "print(*) with internal information"),
        output_for(susy_pairs, "print summary of fixed points with labels"),
    )
    @test all(f.multiplet_type == :left_chiral for f in susy.fields)
    @test all(length(f.space_group_charges) == 5 for f in susy.fields)
    @test all(isempty(f.r_charges) for f in susy.fields) # this Geometry exposes no discrete R symmetry

    field_output = output_for(susy_pairs, "print(*) with internal information")
    @test_throws ErrorException OrbifolderBridge._parse_field_details(replace(field_output, "field no." => "field index"; count = 1))

    optional_charges = """
        gauge boson: A_1
      sector (k,l)        : (1, 2)
      fixed point n_a     : (0, 1/2, 0, 0, 0, 0)
      space group charges : (1/3, 2/3)
      representation      : ( 8)_v  U(1): ()
      right-moving q_sh   : (0, 1, 0, 0)
      R charges           : (1/3, -1/3)
      field no.           : 42
    """
    charged = only(OrbifolderBridge._parse_field_details(optional_charges))
    @test charged.multiplet_type == :gauge_boson
    @test charged.constructing_translation == [0, 1 // 2, 0, 0, 0, 0]
    @test charged.space_group_charges == [1 // 3, 2 // 3]
    @test charged.r_charges == [1 // 3, -1 // 3]
end

@testset "parse_twist" begin
    t1 = parse_twist(output_for(
        split_transcript(read(joinpath(@__DIR__, "fixtures", "nonsusy", "z3_1_1_summary.txt"), String)),
        "print twist",
    ))
    @test t1.vectors == [[0 // 1, 1 // 3, 1 // 3, -2 // 3]]

    t2 = parse_twist(output_for(
        split_transcript(read(joinpath(@__DIR__, "fixtures", "susy", "mssm0_summary.txt"), String)),
        "print twist",
    ))
    @test t2.vectors == [[0 // 1, 0 // 1, 1 // 3, -1 // 3], [0 // 1, 1 // 3, 0 // 1, -1 // 3]]

    @test_throws ErrorException parse_twist("no twist here")
end

@testset "parse_shift_vectors" begin
    pairs = split_transcript(read(joinpath(@__DIR__, "fixtures", "susy", "mssm0_summary.txt"), String))
    shifts = parse_shift_vectors(output_for(pairs, "print shift"))
    @test length(shifts) == 2
    @test shifts[1].label == "V_1"
    @test length(shifts[1].vector) == 16
    @test shifts[1].vector[1:8] == [-2 // 3, 0, 0, 0, 0, 0, 2 // 3, 4 // 3]
    @test shifts[1].vector[9:16] == [-2 // 3, -2 // 3, 0, 0, 0, 0, 1, 1]

    @test_throws ErrorException parse_shift_vectors("no shift here")
end

@testset "parse_wilson_lines" begin
    pairs = split_transcript(read(joinpath(@__DIR__, "fixtures", "susy", "mssm0_wilsonlines.txt"), String))
    wl = parse_wilson_lines(output_for(pairs, "print Wilson lines"))
    @test length(wl.lines) == 6
    @test [l.label for l in wl.lines] == ["W_1", "W_2", "W_3", "W_4", "W_5", "W_6"]
    @test all(length(l.vector) == 16 for l in wl.lines)
    @test wl.identifications == [("W_1", "W_2"), ("W_3", "W_4"), ("W_5", "W_6")]
    @test wl.orders == [3, 3, 3, 3, 3, 3]
    @test wl.lines[1].vector == fill(0 // 1, 16)
    @test wl.lines[3].vector == wl.lines[4].vector

    nonsusy_pairs =
        split_transcript(read(joinpath(@__DIR__, "fixtures", "nonsusy", "z3_1_1_summary.txt"), String))
    wl2 = parse_wilson_lines(output_for(nonsusy_pairs, "print Wilson lines"))
    @test length(wl2.lines) == 6

    @test_throws ErrorException parse_wilson_lines("no Wilson lines here")
end
