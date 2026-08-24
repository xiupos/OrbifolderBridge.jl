function _fake_backend_tree(kind::Symbol, banner::AbstractString)
    dir = mktempdir()
    geometry = joinpath(dir, "Geometry")
    mkpath(geometry)
    write(joinpath(geometry, "Geometry_Z3_1_1.txt"), "fixture\n")

    binary = joinpath(dir, kind === :susy ? "orbifolder" : "nonSUSYorbifolder")
    script = if kind === :susy
        "#!/bin/sh\ncat >/dev/null\nprintf '%s\\n' '$banner'\n"
    else
        "#!/bin/sh\nprintf '%s\\n' '$banner'\nprintf '%s\\n' '$banner' > result_\"\$2\"\n"
    end
    write(binary, script)
    chmod(binary, 0o755)
    return dir, binary, geometry
end

@testset "backend banner parsing and capabilities" begin
    dir, binary, geometry = _fake_backend_tree(
        :susy,
        "#  The C++ Orbifolder  #\n#  Version: 1.2.1  #",
    )
    try
        withenv("ORBIFOLDER_BIN" => binary, "ORBIFOLDER_GEOMETRY_DIR" => geometry) do
            info = backend_info(:susy)
            @test info.kind === :susy
            @test info.version == v"1.2.1"
            @test info.binary == binary
            @test info.geometry_dir == geometry
            @test supports(info, :detailed_spectrum)
            @test !supports(info, :effective_couplings)

            result = check_backend(:susy)
            @test result.ok
            @test result.info == info
        end
    finally
        rm(dir; recursive = true)
    end
end

@testset "non-SUSY backend detection" begin
    dir, binary, geometry = _fake_backend_tree(
        :nonsusy,
        "#  Non-SUSY Orbifolder  #\n#  Version: 1.0  #",
    )
    try
        withenv(
            "NONSUSYORBIFOLDER_BIN" => binary,
            "NONSUSYORBIFOLDER_GEOMETRY_DIR" => geometry,
        ) do
            info = backend_info(:nonsusy)
            @test info.kind === :nonsusy
            @test info.version == v"1.0.0"
        end
    finally
        rm(dir; recursive = true)
    end
end

@testset "backend compatibility failures" begin
    for (banner, message) in (
        ("not an orbifolder", "does not identify"),
        ("# The C++ Orbifolder\n# Version: 9.0", "unsupported"),
        ("# Non-SUSY Orbifolder\n# Version: 1.0", "identifies itself"),
    )
        dir, binary, geometry = _fake_backend_tree(:susy, banner)
        try
            withenv("ORBIFOLDER_BIN" => binary, "ORBIFOLDER_GEOMETRY_DIR" => geometry) do
                result = check_backend(:susy)
                @test !result.ok
                @test occursin(message, result.message)
                @test !isempty(result.output)

                err = try
                    run_orbifolder_script(:susy, ["print summary"])
                    nothing
                catch e
                    e
                end
                @test err isa BackendCompatibilityError
                @test occursin(banner, err.output)
            end
        finally
            rm(dir; recursive = true)
        end
    end

    mktempdir() do dir
        binary = joinpath(dir, "orbifolder")
        write(binary, "#!/bin/sh\n")
        chmod(binary, 0o644)
        geometry = joinpath(dir, "Geometry")
        mkpath(geometry)
        withenv("ORBIFOLDER_BIN" => binary, "ORBIFOLDER_GEOMETRY_DIR" => geometry) do
            result = check_backend(:susy)
            @test !result.ok
            @test occursin("not executable", result.message)
        end
    end
end
