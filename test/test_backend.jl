function _fake_backend_tree(kind::Symbol, banner::AbstractString)
    dir = mktempdir()
    geometry = joinpath(dir, "Geometry")
    mkpath(geometry)
    write(joinpath(geometry, "Geometry_Z3_1_1.txt"), "fixture\n")

    binary = joinpath(dir, kind === :susy ? "orbifolder" : "nonSUSYorbifolder")
    # Every fake launch appends a line, so tests can assert how many
    # subprocesses an operation actually spawned.
    tally = "echo x >> \"$(joinpath(dir, "launches"))\"\n"
    script = if kind === :susy
        "#!/bin/sh\n$(tally)cat >/dev/null\nprintf '%s\\n' '$banner'\n"
    else
        "#!/bin/sh\n$(tally)printf '%s\\n' '$banner'\nprintf '%s\\n' '$banner' > result_\"\$2\"\n"
    end
    write(binary, script)
    chmod(binary, 0o755)
    return dir, binary, geometry
end

_launch_count(dir) =
    isfile(joinpath(dir, "launches")) ? countlines(joinpath(dir, "launches")) : 0

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
            @test supports(info, :field_vevs)
            @test supports(info, :unbroken_gauge_group)
            # supports() is a membership test over a fixed tuple, so any
            # symbol outside the table is silently false -- which is how an
            # earlier assertion here passed while naming a capability
            # (:effective_couplings) that was never in the table at all.
            # :flatness_analysis is an explicit ROADMAP non-goal, asserted
            # here only to pin that fail-closed behaviour deliberately.
            @test !supports(info, :flatness_analysis)

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
            @test supports(info, :vev_configuration_mutation)
            @test !supports(info, :field_vevs)
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

@testset "configured paths are resolved to absolute paths" begin
    # Every invocation runs with dir = mktempdir(), so a relative configured
    # path would be resolved against that temporary directory and fail to
    # spawn. Regression test: the resolvers must absolutize.
    dir, binary, geometry = _fake_backend_tree(
        :nonsusy,
        "#  Non-SUSY Orbifolder  #\n#  Version: 1.0  #",
    )
    try
        cd(dir) do
            withenv(
                "NONSUSYORBIFOLDER_BIN" => "./nonSUSYorbifolder",
                "NONSUSYORBIFOLDER_GEOMETRY_DIR" => "./Geometry",
            ) do
                @test isabspath(orbifolder_binary(:nonsusy))
                @test isabspath(orbifolder_geometry_dir(:nonsusy))
                @test isfile(orbifolder_binary(:nonsusy))
                # The end-to-end path that previously failed with ENOENT.
                OrbifolderBridge._clear_backend_info_cache!()
                @test backend_info(:nonsusy).version == v"1.0.0"
            end
        end
    finally
        rm(dir; recursive = true)
    end
end

@testset "successful backend probes are cached per binary" begin
    dir, binary, geometry = _fake_backend_tree(
        :nonsusy,
        "#  Non-SUSY Orbifolder  #\n#  Version: 1.0  #",
    )
    try
        withenv(
            "NONSUSYORBIFOLDER_BIN" => binary,
            "NONSUSYORBIFOLDER_GEOMETRY_DIR" => geometry,
        ) do
            OrbifolderBridge._clear_backend_info_cache!()
            first_info = backend_info(:nonsusy)
            @test _launch_count(dir) == 1
            @test backend_info(:nonsusy) == first_info
            @test backend_info(:nonsusy) == first_info
            @test _launch_count(dir) == 1          # cached: no new subprocess

            @test backend_info(:nonsusy; refresh = true) == first_info
            @test _launch_count(dir) == 2          # refresh re-probes

            # check_backend is a diagnostic and must actually run the backend.
            selftest = check_backend(:nonsusy)
            @test selftest.ok
            @test selftest == BackendSelfTest(first_info, true, selftest.message, "")
            @test _launch_count(dir) == 3

            # A rebuilt binary invalidates the cache.
            before = mtime(binary)
            sleep(0.05)
            write(binary, read(binary, String))
            chmod(binary, 0o755)
            @test mtime(binary) != before      # precondition for the next assertion
            backend_info(:nonsusy)
            @test _launch_count(dir) == 4
        end
    finally
        OrbifolderBridge._clear_backend_info_cache!()
        rm(dir; recursive = true)
    end
end
