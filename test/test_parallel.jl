@testset "parallel compute against real binaries (skipped if unavailable)" begin
    nonsusy_bin = joinpath(@__DIR__, "..", "vendor", "nonSUSYorbifolder", "nonSUSYorbifolder")

    if isfile(nonsusy_bin)
        withenv("NONSUSYORBIFOLDER_BIN" => nonsusy_bin, "NONSUSYORBIFOLDER_GEOMETRY_DIR" => nothing) do
            m_z3 = OrbifolderModel(;
                mode = :nonsusy, label = "Z3_1_1", point_group = "Z3_1_1",
                shift = ([0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0], [1 // 3, 1 // 3, -2 // 3, zeros(Int, 13)...]),
            )
            # Second model: same point group family but a distinct (also valid)
            # shift, so a file mixup between concurrent runs would show up as
            # cross-contaminated results instead of silently matching anyway.
            m_z3_alt = OrbifolderModel(;
                mode = :nonsusy, label = "Z3_1_1_alt", point_group = "Z3_1_1",
                shift = ([0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0], [1 // 3, -2 // 3, 1 // 3, zeros(Int, 13)...]),
            )

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
