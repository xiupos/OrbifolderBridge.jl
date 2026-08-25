_coupling_fixture(parts...) = joinpath(@__DIR__, "fixtures", parts...)

function _susy_coupling_test_data()
    model = only(parse_orbifolder_models(
        read(_coupling_fixture("susy", "modelMSSM0.txt"), String);
        mode = :susy,
    ))
    transcript = read(_coupling_fixture("susy", "mssm0_detailed.txt"), String)
    pairs = split_transcript(transcript)
    detailed = parse_detailed_spectrum(
        output_for(pairs, "print summary"),
        output_for(pairs, "print(*) with internal information"),
        output_for(pairs, "print summary of fixed points with labels"),
    )
    return model, detailed
end

@testset "coupling request and command rendering" begin
    request = CouplingRequest([FieldID(11), FieldID(37), FieldID(39)])
    @test request.allowed_fields === nothing
    @test_throws ArgumentError CouplingRequest([FieldID(11), FieldID(37)])
    @test_throws ArgumentError CouplingRequest(
        [FieldID(11), FieldID(37), FieldID(39)];
        allowed_fields = [FieldID(11), FieldID(11)],
    )

    _, detailed = _susy_coupling_test_data()
    labels = OrbifolderBridge._coupling_labels(request, detailed.fields)
    @test OrbifolderBridge._coupling_command(request, labels) ==
          "create coupling(F_1 F_11 F_13)"

    restricted = CouplingRequest(
        request.fields;
        allowed_fields = [FieldID(11), FieldID(37)],
    )
    @test OrbifolderBridge._coupling_command(restricted, labels) ==
          "create coupling(F_1 F_11 F_13) allowed fields(F_1 F_11)"
    @test_throws ArgumentError OrbifolderBridge._coupling_labels(
        CouplingRequest([FieldID(11), FieldID(37), FieldID(999)]),
        detailed.fields,
    )
    @test OrbifolderBridge._sanitize_coupling_transcript("PID 123 done; PID 9") ==
          "PID <redacted> done; PID <redacted>"
    term = CouplingTerm([FieldID(11), FieldID(37), FieldID(11), FieldID(39)])
    @test OrbifolderBridge._term_involves(term, [FieldID(11), FieldID(11)])
    @test !OrbifolderBridge._term_involves(term, fill(FieldID(11), 3))
end

@testset "native coupling-file parser" begin
    model, detailed = _susy_coupling_test_data()
    source = read(_coupling_fixture("susy", "couplings_order3.txt"), String)
    @test parse_couplings(source, model, detailed.fields) == [
        CouplingTerm([FieldID(11), FieldID(37), FieldID(39)]),
    ]
    @test parse_couplings(source, model, detailed) ==
          parse_couplings(source, model, detailed.fields)

    header = join(first(split(source, '\n'), 9), '\n') * '\n'
    @test isempty(parse_couplings(header, model, detailed.fields))

    for malformed in (
        "",
        replace(source, "E8xE8" => "Spin32"),
        replace(source, "-2/3" => "-1/3"; count = 1),
        replace(source, "11 37 39" => "11 bad 39"),
        replace(source, "11 37 39" => "11 37"),
        replace(source, "11 37 39" => "11 37 999"),
        source * "11 37 39\n",
    )
        err = try
            parse_couplings(malformed, model, detailed.fields)
            nothing
        catch e
            e
        end
        @test err isa CouplingParseError
        @test err.source == malformed
    end
end

@testset "non-interactive coupling protocol fixture" begin
    transcript = read(_coupling_fixture("susy", "couplings_order3_transcript.txt"), String)
    pairs = split_transcript(transcript)
    @test occursin(
        "1 couplings created.",
        output_for(pairs, "wait(1)"),
    )
    @test occursin(
        "Couplings saved to file",
        output_for(pairs, "save couplings(bridge_couplings.txt)"),
    )
    @test !occursin(r"PID\s+[0-9]+", transcript)
    @test OrbifolderBridge._reported_coupling_count(transcript) == 1
    @test OrbifolderBridge._reported_coupling_count(replace(
        transcript,
        "1 couplings created." => "1 couplings created.\n  2 couplings created.",
    )) == 3
    for malformed in (
        replace(transcript, "wait(1)" => "wait(2)"),
        replace(transcript, "1 couplings created." => "coupling calculation failed"),
        replace(transcript, "waiting done." => ""),
    )
        err = try
            OrbifolderBridge._reported_coupling_count(malformed)
            nothing
        catch e
            e
        end
        @test err isa CouplingExecutionError
        @test err.transcript == malformed
    end
end

@testset "coupling search validation" begin
    model, _ = _susy_coupling_test_data()
    config = VEVConfigurationRef("TestConfig1")
    cubic = CouplingRequest([FieldID(11), FieldID(37), FieldID(39)])
    quartic = CouplingRequest([FieldID(15), FieldID(32), FieldID(131), FieldID(333)])
    @test_throws ArgumentError search_couplings(
        model, config, [cubic]; max_order = 2,
    )
    @test_throws ArgumentError search_couplings(
        model, config, [quartic]; max_order = 3,
    )
    @test_throws ArgumentError search_couplings(
        model, config, [cubic, cubic]; max_order = 3,
    )
end

@testset "coupling backend capability" begin
    @test :couplings in OrbifolderBridge._BACKEND_CAPABILITIES[(:susy, v"1.2.1")]
    @test !(:couplings in OrbifolderBridge._BACKEND_CAPABILITIES[(:nonsusy, v"1.0.0")])
end

@testset "OSCAR coupling polynomials and exact VEV substitution" begin
    cubic = CouplingTerm([FieldID(11), FieldID(37), FieldID(39)])
    repeated = CouplingTerm([FieldID(11), FieldID(11), FieldID(39)])
    data = coupling_polynomial_ring([cubic, repeated])
    @test getfield.(data.fields, :number) == [11, 37, 39]
    @test string(coupling_polynomial(data, cubic)) == "f_11*f_37*f_39"
    @test string(coupling_polynomial(data, repeated)) == "f_11^2*f_39"
    @test coupling_polynomial(data, CouplingTerm[]) == zero(data.ring)
    @test_throws ArgumentError coupling_polynomial_ring(FieldID[])
    @test_throws ArgumentError coupling_polynomial_ring([FieldID(11), FieldID(11)])
    @test_throws ArgumentError coupling_polynomial(
        data, CouplingTerm([FieldID(999), FieldID(11), FieldID(39)]),
    )

    substitution = exact_vev_substitution(data, [FieldID(39)])
    @test string(substitution.homomorphism(coupling_polynomial(data, cubic))) ==
          "f_11*f_37*v_39"
    effective = apply_vev_substitution(substitution, [cubic, repeated])
    @test getfield.(effective, :source) == [cubic, repeated]
    @test string.(getfield.(effective, :polynomial)) ==
          ["f_11*f_37*v_39", "f_11^2*v_39"]
    @test all(value -> value.vev_fields == [FieldID(39)], effective)
    @test_throws ArgumentError exact_vev_substitution(
        data, [FieldID(39), FieldID(39)],
    )
    @test_throws ArgumentError exact_vev_substitution(data, [FieldID(999)])
end

@testset "effective superpotential parser" begin
    _, detailed = _susy_coupling_test_data()
    source = CouplingTerm([FieldID(11), FieldID(37), FieldID(39)])
    transcript = read(_coupling_fixture("susy", "effective_superpotential.txt"), String)
    output = output_for(split_transcript(transcript), "print effective superpotential")
    @test parse_effective_couplings(output, detailed, [source]) == [
        UpstreamEffectiveCoupling(source, [FieldID(11), FieldID(37)], [FieldID(39)]),
    ]
    @test isempty(parse_effective_couplings("W_eff = 0", detailed, CouplingTerm[]))

    second = CouplingTerm([FieldID(11), FieldID(37), FieldID(41)])
    grouped = parse_effective_couplings(
        "W_eff = F_1 F_11 (<F_13> + <F_15>)",
        detailed,
        [source, second],
    )
    @test getfield.(grouped, :source) == [source, second]
    @test getfield.(grouped, :vev_fields) == [[FieldID(39)], [FieldID(41)]]

    for malformed in (
        "no potential",
        "W_eff = F_1 (",
        "W_eff = F_999",
        "W_eff = F_1 F_11",
        "W_eff = F_1 F_11 <F_13> + F_1 F_11 <F_15>",
    )
        @test_throws CouplingParseError parse_effective_couplings(
            malformed, detailed, [source],
        )
    end
end
