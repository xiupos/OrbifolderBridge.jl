@testset "mass-matrix request validation" begin
    cubic = CouplingRequest([FieldID(11), FieldID(15), FieldID(39)])
    request = MassMatrixRequest(
        [FieldID(11)], [FieldID(15)], [cubic]; max_order = 3,
    )
    @test request.max_order == 3
    @test_throws ArgumentError MassMatrixRequest(FieldID[], [FieldID(15)], [cubic]; max_order = 3)
    @test_throws ArgumentError MassMatrixRequest([FieldID(11)], FieldID[], [cubic]; max_order = 3)
    @test_throws ArgumentError MassMatrixRequest([FieldID(11)], [FieldID(15)], CouplingRequest[]; max_order = 3)
    @test_throws ArgumentError MassMatrixRequest([FieldID(11)], [FieldID(11), FieldID(15)], [cubic]; max_order = 3)
    @test_throws ArgumentError MassMatrixRequest([FieldID(11)], [FieldID(15)], [cubic]; max_order = 0)
end

@testset "mass-matrix parser and provenance" begin
    _, detailed = _susy_coupling_test_data()
    captured = read(
        _coupling_fixture("susy", "mass_matrix_1x1_transcript.txt"), String,
    )
    captured_output = output_for(
        split_transcript(captured), "print mass matrix(1) max order(3)",
    )
    captured_source = CouplingTerm([FieldID(11), FieldID(37), FieldID(39)])
    captured_matrix = parse_mass_matrix(
        captured_output, [FieldID(11)], [FieldID(37)], detailed.fields,
        [captured_source],
    )
    @test captured_matrix.entries[1, 1] == [
        MassMatrixTerm(captured_source, [FieldID(39)]),
    ]

    rows = [FieldID(11), FieldID(37)]
    columns = [FieldID(15), FieldID(32)]
    sources = [
        CouplingTerm([FieldID(11), FieldID(15), FieldID(39)]),
        CouplingTerm([FieldID(37), FieldID(15), FieldID(41)]),
        CouplingTerm([FieldID(37), FieldID(15), FieldID(39), FieldID(41)]),
        CouplingTerm([FieldID(37), FieldID(32), FieldID(39)]),
    ]
    output = read(_coupling_fixture("susy", "mass_matrix_2x2.txt"), String)
    parsed = parse_mass_matrix(output, rows, columns, detailed.fields, sources)
    @test parsed.rows == rows
    @test parsed.columns == columns
    @test !parsed.transposed
    @test size(parsed.entries) == (2, 2)
    @test getfield.(parsed.entries[1, 1], :source) == sources[1:1]
    @test isempty(parsed.entries[1, 2])
    @test getfield.(parsed.entries[2, 1], :source) == sources[2:3]
    @test getfield.(parsed.entries[2, 1], :vev_fields) == [
        [FieldID(41)], [FieldID(39), FieldID(41)],
    ]
    @test getfield.(parsed.entries[2, 2], :source) == sources[4:4]

    transposed = "  mass matrix: C_i M_ij R_j\t(  2 x  2 matrix)\n" *
                 "\t<F_13>\t\t<F_15> + <F_13> <F_15>\n" *
                 "\t0\t\t<F_13>\n"
    parsed_t = parse_mass_matrix(transposed, rows, columns, detailed.fields, sources)
    @test parsed_t.transposed
    @test parsed_t.rows == columns
    @test parsed_t.columns == rows

    same = parse_mass_matrix(
        "mass matrix: R_i M_ij R_j\t(  1 x  1 matrix)\n\t<F_13>\n",
        [FieldID(11)], [FieldID(11)], detailed.fields,
        [CouplingTerm([FieldID(11), FieldID(11), FieldID(39)])];
        row_label = "R", column_label = "R",
    )
    @test !same.transposed
    @test same.entries[1, 1][1].vev_fields == [FieldID(39)]

    for malformed in (
        "no matrix",
        replace(output, "2 x  2" => "3 x  2"),
        replace(output, "<F_13>" => "s"; count = 1),
        replace(output, "<F_13>" => "<F_999>"; count = 1),
        replace(output, "\t\t0" => ""; count = 1),
    )
        err = try
            parse_mass_matrix(malformed, rows, columns, detailed.fields, sources)
            nothing
        catch e
            e
        end
        @test err isa MassMatrixParseError
        @test err.source == malformed
    end
end

@testset "OSCAR polynomial mass matrix" begin
    _, detailed = _susy_coupling_test_data()
    source = CouplingTerm([FieldID(11), FieldID(15), FieldID(39)])
    request = MassMatrixRequest(
        [FieldID(11)], [FieldID(15)], [CouplingRequest(source.fields)]; max_order = 3,
    )
    entries = Matrix{Vector{MassMatrixTerm}}(undef, 1, 1)
    entries[1, 1] = [MassMatrixTerm(source, [FieldID(39)])]
    result = MassMatrixResult(
        VEVConfigurationSpec(name = "MatrixTest1", assignments = [VEVAssignment(FieldID(39), 1)]),
        request, request.rows, request.columns, entries, [source], false,
        BackendInfo(:susy, v"1.2.1", "orbifolder", "Geometry", (:mass_matrices,)), "", "",
    )
    ring = coupling_polynomial_ring(source.fields)
    substitution = exact_vev_substitution(ring, [FieldID(39)])
    matrix_value = mass_matrix_polynomial(substitution, result)
    @test size(matrix_value) == (1, 1)
    @test string(matrix_value[1, 1]) == "v_39"
    specialized = specialize_mass_matrix(
        substitution, result, Dict(FieldID(39) => 3//2),
    )
    @test specialized[1, 1] == 3//2
    @test_throws ArgumentError specialize_mass_matrix(
        substitution, result, Dict{FieldID,Rational{Int}}(),
    )
    @test_throws ArgumentError specialize_mass_matrix(
        substitution, result, Dict(FieldID(39) => 1//1, FieldID(11) => 1//1),
    )
end

@testset "mass-matrix backend capability" begin
    @test :mass_matrices in OrbifolderBridge._BACKEND_CAPABILITIES[(:susy, v"1.2.1")]
    @test !(:mass_matrices in OrbifolderBridge._BACKEND_CAPABILITIES[(:nonsusy, v"1.0.0")])
end
