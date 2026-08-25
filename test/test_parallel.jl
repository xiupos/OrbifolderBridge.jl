@testset "parallel compute against real binaries (skipped if unavailable)" begin
    nonsusy_bin = joinpath(@__DIR__, "..", "vendor", "nonSUSYorbifolder", "nonSUSYorbifolder")

    if isfile(nonsusy_bin)
        withenv("NONSUSYORBIFOLDER_BIN" => nonsusy_bin, "NONSUSYORBIFOLDER_GEOMETRY_DIR" => nothing) do
            m_z3 = OrbifolderModel(;
                mode = :nonsusy, label = "Z3_1_1", point_group = "Z3_1_1",
                shift = ([0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0], [1 // 3, 1 // 3, -2 // 3, zeros(Int, 13)...]),
            )
            # Second model: same point group and compactification shift, but
            # with a nontrivial (order-3, W_1 = W_2 identified) Wilson line
            # breaking the second E8 further, SO(16) -> SO(10) x SU(3). This
            # gives a genuinely different gauge group and field count (not
            # merely a coordinate permutation of the same embedding, as an
            # earlier version of this fixture used), so a file mixup between
            # concurrent runs shows up as cross-contaminated results instead
            # of silently matching anyway.
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

            # Interleave many copies of both models so concurrent asyncmap
            # tasks are genuinely racing against each other, not just running
            # N copies of an identical model.
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
end
