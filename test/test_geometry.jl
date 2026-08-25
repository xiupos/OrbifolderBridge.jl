@testset "available space groups" begin
    susy_text = read(joinpath(@__DIR__, "fixtures", "susy", "geometry.txt"), String)
    susy = parse_available_space_groups(susy_text; backend = :susy)
    @test length(susy) == 2
    @test susy[1] == SpaceGroupInfo(
        :susy, 1, [3, 3], "Z3xZ3_1", "", "Geometry/Geometry_Z3xZ3_1_1.txt",
    )
    @test susy[2].additional_label == "roto-translation"

    nonsusy_text = read(joinpath(@__DIR__, "fixtures", "nonsusy", "geometry.txt"), String)
    nonsusy = parse_available_space_groups(nonsusy_text; backend = :nonsusy)
    @test only(nonsusy).point_group_orders == [3]
    @test only(nonsusy).backend == :nonsusy

    empty = parse_available_space_groups("available Z_7 space groups: none"; backend = :susy)
    @test isempty(empty)
    err = try
        parse_available_space_groups("format drift"; backend = :susy)
        nothing
    catch e
        e
    end
    @test err isa GeometryParseError
    @test err.output == "format drift"
    @test_throws ArgumentError parse_available_space_groups(susy_text; backend = :bogus)
    @test_throws GeometryParseError parse_available_space_groups(
        replace(susy_text, "     2 |" => "     3 |"); backend = :susy,
    )
end

@testset "space group metadata" begin
    for (mode, file, orders, lattice, arity) in [
        (:susy, "susy", [3, 3], "Z3xZ3_1", 2),
        (:nonsusy, "nonsusy", [3], "Z3_1", 3),
    ]
        point, space = split(
            read(joinpath(@__DIR__, "fixtures", file, "space_group.txt"), String),
            "---SPACE---"; limit = 2,
        )
        metadata = parse_space_group_metadata(
            point, space; backend = mode, geometry_file = "Geometry/example.txt",
        )
        @test metadata.point_group_orders == orders
        @test metadata.lattice_label == lattice
        @test metadata.geometry_file == "Geometry/example.txt"
        @test length(metadata.generators) == 3
        @test all(length(g.sector.coordinates) == arity for g in metadata.generators)
        @test all(length(g.translation) == 6 for g in metadata.generators)
    end

    point, space = split(
        read(joinpath(@__DIR__, "fixtures", "susy", "space_group.txt"), String),
        "---SPACE---"; limit = 2,
    )
    @test_throws GeometryParseError parse_space_group_metadata(
        point, replace(space, "Z_3 x Z_3" => "Z_2 x Z_2");
        backend = :susy, geometry_file = "Geometry/example.txt",
    )
    @test_throws GeometryParseError parse_space_group_metadata(
        point, replace(space, "(1, 0)" => "(1, 0, 0)"; count = 1);
        backend = :susy, geometry_file = "Geometry/example.txt",
    )
end

@testset "structured localizations" begin
    pairs = split_transcript(read(
        joinpath(@__DIR__, "fixtures", "nonsusy", "z3_1_1_detailed.txt"), String,
    ))
    detailed = parse_detailed_spectrum(
        output_for(pairs, "print summary"),
        output_for(pairs, "print(*) with internal information"),
        output_for(pairs, "print summary of fixed points with labels"),
    )
    locations = localizations(detailed)
    @test !isempty(locations)
    @test sum(length(loc.fields) for loc in locations) == length(detailed.fields)
    @test length(unique(id for loc in locations for id in loc.fields)) == length(detailed.fields)
    @test all(length(loc.constructing_element.sector.coordinates) == 3 for loc in locations)
    @test all(length(loc.constructing_element.translation) == 6 for loc in locations)
    @test all(length(loc.local_shift) == 16 for loc in locations)

    loc = first(locations)
    fields = fields_at(loc, detailed)
    @test getfield.(fields, :id) == loc.fields
    data = local_gauge_data(loc, detailed)
    @test data.localization == loc
    @test data.fields == fields
    bad = Localization(loc.label, loc.constructing_element, loc.local_shift, [FieldID(-1)])
    @test_throws ArgumentError fields_at(bad, detailed)
end
