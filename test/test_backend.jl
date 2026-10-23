@testset "backend banner validation" begin
    validate = OrbifolderBridge._validate_backend_output
    @test validate(:susy, "#  The C++ Orbifolder  #\n#  Version: 1.2.1  #") == v"1.2.1"
    @test validate(:nonsusy, "#  Non-SUSY Orbifolder  #\n#  Version: 1.0  #") == v"1.0.0"

    for (kind, banner, message) in (
        (:susy, "not an orbifolder", "does not identify"),
        (:susy, "# The C++ Orbifolder\n# no version line", "does not contain a version"),
        (:susy, "# The C++ Orbifolder\n# Version: 9.0", "unsupported"),
        (:susy, "# Non-SUSY Orbifolder\n# Version: 1.0", "identifies itself"),
    )
        err = try
            validate(kind, banner)
            nothing
        catch e
            e
        end
        @test err isa BackendCompatibilityError
        @test occursin(message, err.message)
        @test err.output == banner
    end
end

@testset "backend info against the bundled JLL (skipped if unavailable)" begin
    for (mode, version) in (:susy => v"1.2.1", :nonsusy => v"1.0.0")
        _with_jll_backend(mode) do
            info = backend_info(mode; refresh = true)
            @test info.kind === mode
            @test info.version == version
            @test info.binary == orbifolder_binary(mode)
            @test info.geometry_dir == orbifolder_geometry_dir(mode)
            @test supports(info, :detailed_spectrum)
            @test supports(info, :field_vevs) == (mode === :susy)
            # supports() is a membership test over a fixed tuple, so any symbol
            # outside the table is silently false. :flatness_analysis is an
            # explicit ROADMAP non-goal, asserted to pin that fail-closed behaviour.
            @test !supports(info, :flatness_analysis)

            result = check_backend(mode)
            @test result.ok
            @test result.info == info
        end
    end
end
