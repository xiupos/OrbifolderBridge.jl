@testset "parallel compute against the bundled JLL (skipped if unavailable)" begin
    _with_jll_backend(:nonsusy) do
        m_z3 = OrbifolderModel(;
            mode = :nonsusy, label = "Z3_1_1", point_group = "Z3_1_1",
            shift = ([0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0], [1 // 3, 1 // 3, -2 // 3, zeros(Int, 13)...]),
        )
        # A Wilson line gives a different gauge group and field count, so a
        # file mixup between concurrent runs shows up as wrong results.
        _z3_alt_wilson_line = Rational{Int}[
            0, 0, 0, 0, 0, 0, 0, 0, 1 // 3, 1 // 3, -2 // 3, 0, 0, 0, 0, 0,
        ]
        m_z3_alt = OrbifolderModel(;
            mode = :nonsusy, label = "Z3_1_1_alt", point_group = "Z3_1_1",
            shift = ([0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0], [1 // 3, 1 // 3, -2 // 3, zeros(Int, 13)...]),
            wilson_lines = [
                _z3_alt_wilson_line, _z3_alt_wilson_line,
                zeros(Rational{Int}, 16), zeros(Rational{Int}, 16),
                zeros(Rational{Int}, 16), zeros(Rational{Int}, 16),
            ],
        )
        @test compute_gauge_group(m_z3_alt) != compute_gauge_group(m_z3)

        # Interleave both models so concurrent tasks race on distinct inputs.
        models = [isodd(i) ? m_z3 : m_z3_alt for i in 1:20]
        expected = [isodd(i) ? compute_spectrum(m_z3) : compute_spectrum(m_z3_alt) for i in 1:20]

        specs = compute_spectra(models; ntasks = 6)
        @test specs == expected

        gauge_groups = compute_gauge_groups(models; ntasks = 6)
        @test gauge_groups == [s.gauge_group for s in expected]

        twists = compute_twists(models; ntasks = 6)
        @test all(t -> length(t.vectors) == 1, twists)

        wls = compute_wilson_lines_batch(models; ntasks = 6)
        @test all(wl -> wl.orders == [3, 3, 3, 3, 3, 3], wls)

        shifts = compute_shift_vectors_batch(models; ntasks = 6)
        @test all(s -> length(s) == 1, shifts)
    end
end
