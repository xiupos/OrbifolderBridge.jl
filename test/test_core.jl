using OrbiFolder_jll: OrbiFolder_jll
using NonSUSYOrbiFolder_jll: NonSUSYOrbiFolder_jll

@testset "mode validation" begin
    @test_throws ArgumentError orbifolder_binary(:bogus)
    @test_throws ArgumentError orbifolder_geometry_dir(:bogus)
end

@testset "backend resolution from the JLL" begin
    for (mode, jll) in (:susy => OrbiFolder_jll, :nonsusy => NonSUSYOrbiFolder_jll)
        if jll.is_available()
            @test dirname(orbifolder_binary(mode)) == joinpath(jll.artifact_dir, "bin")
            @test orbifolder_geometry_dir(mode) == joinpath(jll.artifact_dir, "bin", "Geometry")
            @test isdir(orbifolder_geometry_dir(mode))
        else
            @test_throws ErrorException orbifolder_binary(mode)
            @test_throws ErrorException orbifolder_geometry_dir(mode)
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

@testset "run_orbifolder_script against the bundled JLL (skipped if unavailable)" begin
    # Launches the JLL executable with its bundled Geometry/, which also covers
    # the environment its dependency artifacts need.
    for (mode, model, label, expected) in (
        (:nonsusy, "modelZ3_1_1.txt", "Z3_1_1", "SO(10) x SU(3) and SO(16) and U(1)"),
        (:susy, "modelMSSM0.txt", "MSSM0", "SU(3) x SU(2) and SU(3) x SU(2) x SU(2) and U(1)^9"),
    )
        _with_jll_backend(mode) do
            out = run_orbifolder_script(
                mode,
                ["load orbifolds($model)", "cd $label", "cd spectrum", "print summary"];
                files = Dict(model => read(joinpath(@__DIR__, "fixtures", String(mode), model), String)),
            )
            @test occursin(expected, out)
        end
    end
end
