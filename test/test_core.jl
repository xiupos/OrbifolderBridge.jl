@testset "mode validation" begin
    @test_throws ArgumentError orbifolder_binary(:bogus)
    @test_throws ArgumentError orbifolder_geometry_dir(:bogus)
end

@testset "binary detection" begin
    withenv("ORBIFOLDER_BIN" => nothing, "NONSUSYORBIFOLDER_BIN" => nothing) do
        @test_throws ErrorException orbifolder_binary(:susy)
    end

    mktempdir() do dir
        binpath = joinpath(dir, "fake_orbifolder")
        write(binpath, "#!/bin/sh\necho fake\n")
        chmod(binpath, 0o755)
        withenv("ORBIFOLDER_BIN" => binpath) do
            @test orbifolder_binary(:susy) == binpath
        end
    end
end

@testset "geometry dir fallback next to binary" begin
    mktempdir() do treeroot
        # nonSUSY-style layout: binary and Geometry/ as siblings
        binpath = joinpath(treeroot, "nonSUSYorbifolder")
        write(binpath, "#!/bin/sh\n")
        mkpath(joinpath(treeroot, "Geometry"))
        withenv("NONSUSYORBIFOLDER_BIN" => binpath, "NONSUSYORBIFOLDER_GEOMETRY_DIR" => nothing) do
            @test orbifolder_geometry_dir(:nonsusy) == joinpath(treeroot, "Geometry")
        end

        # SUSY-style layout: binary two levels below the tree root
        deepbin = joinpath(treeroot, "src", "orbifolder", "orbifolder")
        mkpath(dirname(deepbin))
        write(deepbin, "#!/bin/sh\n")
        withenv("ORBIFOLDER_BIN" => deepbin, "ORBIFOLDER_GEOMETRY_DIR" => nothing) do
            @test isdir(orbifolder_geometry_dir(:susy))
            @test realpath(orbifolder_geometry_dir(:susy)) == realpath(joinpath(treeroot, "Geometry"))
        end
    end
end

@testset "run_capture" begin
    @test run_capture(`echo hello`) == "hello\n"
    @test run_capture(`cat`; input = "hi there") == "hi there"

    err = try
        run_capture(`false`)
        nothing
    catch e
        e
    end
    @test err isa OrbifolderProcessError
    @test err.exitcode == 1

    terr = try
        run_capture(`sleep 5`; timeout = 0.2)
        nothing
    catch e
        e
    end
    @test terr isa OrbifolderTimeoutError
end

@testset "run_orbifolder_script against real binaries (skipped if unavailable)" begin
    nonsusy_bin = joinpath(@__DIR__, "..", "vendor", "nonSUSYorbifolder", "nonSUSYorbifolder")
    susy_bin = joinpath(@__DIR__, "..", "vendor", "orbifolder", "src", "orbifolder", "orbifolder")

    if isfile(nonsusy_bin)
        withenv("NONSUSYORBIFOLDER_BIN" => nonsusy_bin, "NONSUSYORBIFOLDER_GEOMETRY_DIR" => nothing) do
            model = read(joinpath(@__DIR__, "fixtures", "nonsusy", "modelZ3_1_1.txt"), String)
            out = run_orbifolder_script(
                :nonsusy,
                ["load orbifolds(modelZ3_1_1.txt)", "cd Z3_1_1", "cd spectrum", "print summary"];
                files = Dict("modelZ3_1_1.txt" => model),
            )
            @test occursin("SO(10) x SU(3) and SO(16) and U(1)", out)
        end
    end

    if isfile(susy_bin)
        withenv("ORBIFOLDER_BIN" => susy_bin, "ORBIFOLDER_GEOMETRY_DIR" => nothing) do
            model = read(joinpath(@__DIR__, "fixtures", "susy", "modelMSSM0.txt"), String)
            out = run_orbifolder_script(
                :susy,
                ["load orbifolds(modelMSSM0.txt)", "cd MSSM0", "cd spectrum", "print summary"];
                files = Dict("modelMSSM0.txt" => model),
            )
            @test occursin("SU(3) x SU(2) and SU(3) x SU(2) x SU(2) and U(1)^9", out)
        end
    end
end
