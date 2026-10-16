using Test
using AShareChips
using Dates: Date

@testset "Histogram comparisons" begin
    @testset "Translated uniforms and disjoint supports" begin
        reference = ChipDistribution(PriceGrid([1,3]), [1])
        shifted = ChipDistribution(PriceGrid([1.75,3.75]), [1])
        result = compare_distributions(shifted, reference; quantiles=[0,0.1,0.5,0.9,1])
        @test result.wasserstein1 ≈ 0.75
        @test result.max_cdf_error ≈ 0.375
        @test result.mean_cost_error ≈ 0.75
        @test result.quantile_errors ≈ fill(0.75,5)
        @test result.prices == [2.0]
        @test result.profit_errors ≈ [-0.375]
        @test result.comparison_points == [1,1.75,3,3.75]

        disjoint = compare_distributions(
            ChipDistribution(PriceGrid([4,6]), [1]),
            ChipDistribution(PriceGrid([1,2]), [1]))
        @test disjoint.wasserstein1 ≈ 3.5
        @test disjoint.max_cdf_error == 1
        @test disjoint.mean_cost_error ≈ 3.5
        @test disjoint.quantile_errors ≈ [3.1,3.5,3.9]
        @test disjoint.profit_errors == [-0.5]
    end

    @testset "CDF crossings are split inside an interval" begin
        grid = PriceGrid([1,2,3,4])
        estimate = ChipDistribution(grid,[3,4,3])
        reference = ChipDistribution(grid,[1,8,1])
        result = compare_distributions(estimate,reference; prices=[2,2.5,3])
        # Endpoint differences on [2,3] are +0.2 and -0.2. Their zero
        # lies at 2.5; the two triangular areas total 0.1, not 0.2.
        @test result.wasserstein1 ≈ 0.3
        @test result.max_cdf_error ≈ 0.2
        @test result.mean_cost_error ≈ 0 atol=1e-14
        @test result.profit_errors ≈ [0.2,0,-0.2] atol=1e-14
    end

    @testset "Different edges, gaps and equivalent representations" begin
        reference = ChipDistribution(PriceGrid([1,3]), [1])
        estimate = ChipDistribution(PriceGrid([1,1.5,2.5,3]), [1,0,1])
        result = compare_distributions(estimate,reference)
        @test result.max_cdf_error == 0.25
        @test result.wasserstein1 == 0.25
        @test result.mean_cost_error == 0
        @test result.quantile_errors ≈ [-0.1,-0.5,0.1]
        @test result.comparison_points == [1,1.5,2.5,3]

        equivalent = ChipDistribution(PriceGrid([0,1,1.5,2,3,5]), [0,1,1,2,0])
        same = compare_distributions(equivalent,reference; quantiles=[0,0.5,1])
        @test same.max_cdf_error == 0
        @test same.wasserstein1 == 0
        @test same.mean_cost_error == 0
        @test same.quantile_errors == zeros(3)
        @test same.profit_errors == [0]
    end

    @testset "Symmetry, ownership, input order and validation" begin
        estimate = ChipDistribution(PriceGrid([1,2,4]), [3,1])
        reference = ChipDistribution(PriceGrid([0,1.5,3,5]), [1,1,2])
        qs, ps = [1.0,0.25,0.0,0.25], [4.0,-1.0,0.0,1.5,4.0]
        before_estimate, before_reference = probabilities(estimate), probabilities(reference)
        forward = compare_distributions(estimate,reference; quantiles=qs,prices=ps)
        backward = compare_distributions(reference,estimate; quantiles=qs,prices=ps)
        @test forward.max_cdf_error ≈ backward.max_cdf_error
        @test forward.wasserstein1 ≈ backward.wasserstein1
        @test forward.mean_cost_error ≈ -backward.mean_cost_error
        @test forward.quantile_errors ≈ -backward.quantile_errors
        @test forward.profit_errors ≈ -backward.profit_errors
        @test forward.quantiles == qs
        @test forward.prices == ps
        @test forward.quantile_errors[2] == forward.quantile_errors[4]
        @test forward.profit_errors[1] == forward.profit_errors[5]
        qs[1], ps[1] = 0.5, 2.0
        @test forward.quantiles[1] == 1
        @test forward.prices[1] == 4
        forward.quantiles[2], forward.prices[2] = 0.5, 2.0
        @test qs[2] == 0.25
        @test ps[2] == -1
        forward.comparison_points[1] = 100
        @test bin_edges(reference)[1] == 0
        @test probabilities(estimate) == before_estimate
        @test probabilities(reference) == before_reference

        empty = compare_distributions(estimate,reference; quantiles=[],prices=[])
        @test isempty(empty.quantiles)
        @test isempty(empty.quantile_errors)
        @test isempty(empty.prices)
        @test isempty(empty.profit_errors)
        generated = compare_distributions(estimate,reference;
            quantiles=(q for q in (0,0.5,1)),prices=(p for p in (1,2)))
        @test generated.quantiles == [0,0.5,1]
        @test generated.prices == [1,2]
        for q in (-0.1,1.1,NaN,Inf,-Inf,"bad")
            @test_throws ArgumentError compare_distributions(estimate,reference; quantiles=[q])
        end
        for p in (NaN,Inf,-Inf,"bad")
            @test_throws ArgumentError compare_distributions(estimate,reference; prices=[p])
        end
        identical = compare_distributions(estimate,estimate)
        @test identical.max_cdf_error == 0
        @test identical.wasserstein1 == 0
        @test identical.mean_cost_error == 0
        @test identical.quantile_errors == zeros(3)
        @test identical.profit_errors == zeros(2)
    end
end

@testset "Grid sensitivity experiments" begin
    bar = DailyBar(low=1,high=3,close=2,turnover=0.2)
    coarse = PriceGrid([1,3])
    irregular = PriceGrid([1,1.25,2.75,3])
    fine = PriceGrid(collect(1:0.5:3))
    reference_grid = PriceGrid(collect(1:0.25:3))

    @testset "Analytic symmetric triangular kernel" begin
        rows = grid_convergence([bar],[coarse,irregular,fine,reference_grid])
        @test length(rows) == 4
        @test [row.bin_count for row in rows] == [1,3,4,8]
        @test [row.max_bin_width for row in rows] == [2,1.5,0.5,0.25]
        # Exact triangle CDF values at quarter-price points give these
        # independently derived polygon areas against its histogram projection.
        @test [row.max_cdf_error for row in rows] ≈ [1/8,1/16,1/32,0]
        @test [row.wasserstein1 for row in rows] ≈ [5/32,1/16,1/32,0]
        @test all(row -> abs(row.mean_cost_error) < 1e-14,rows)
        @test rows[end].quantile_errors == zeros(3)
        @test rows[end].profit_errors == zeros(8)
        @test rows[1].prices == price_centers(reference_grid)
        @test rows[1].quantiles !== rows[2].quantiles
        @test rows[1].prices !== rows[2].prices

        explicit = grid_convergence([bar],[coarse,fine]; reference_grid=reference_grid)
        @test explicit[1].wasserstein1 == rows[1].wasserstein1
        @test explicit[2].wasserstein1 == rows[3].wasserstein1
        first_reference = grid_convergence([bar],[coarse,fine]; reference_grid=coarse)
        @test first_reference[1].wasserstein1 == 0
        @test first_reference[1].max_cdf_error == 0
        @test first_reference[2].wasserstein1 > 0
    end

    @testset "Tiny price coordinates and irregular bins" begin
        scale = 1e-300
        tiny_bar = DailyBar(low=scale,high=3scale,close=2scale,turnover=0.2)
        grids = [PriceGrid(scale .* bin_edges(grid)) for grid in
                 (coarse,irregular,fine,reference_grid)]
        rows = grid_convergence([tiny_bar],grids)
        @test [row.max_cdf_error for row in rows] ≈ [1/8,1/16,1/32,0] atol=1e-14
        @test [row.wasserstein1/scale for row in rows] ≈ [5/32,1/16,1/32,0] atol=1e-14
        @test all(row -> isfinite(row.wasserstein1),rows)
    end

    @testset "Simulation keywords, reusable iterators and coverage" begin
        bars = [bar,DailyBar(low=1,high=3,close=1,turnover=0.4)]
        qs, ps = [0.0,0.5,1.0], [0.5,1.75,3.5]
        rows = grid_convergence((b for b in bars),[coarse,fine];
            model=UniformModel(),turnover_model=ExponentialTurnover(),
            adjustments=(PriceAdjustment() for _ in bars),quantiles=qs,prices=ps)
        @test all(row -> row.max_cdf_error == 0,rows)
        @test all(row -> row.wasserstein1 == 0,rows)
        @test rows[1].quantiles == qs
        @test rows[1].prices == ps
        qs[1], ps[1] = 0.25, 1.0
        @test rows[1].quantiles[1] == 0
        @test rows[1].prices[1] == 0.5

        event_bars = [DailyBar(low=8,high=10,close=9,turnover=0),
                      DailyBar(low=4,high=5,close=4.5,turnover=0)]
        events = [PriceAdjustment(),PriceAdjustment(scale=0.5)]
        valid_grid = PriceGrid([2,4,6,8,10,12])
        event_rows = grid_convergence(event_bars,[valid_grid];
                                      model=UniformModel(),adjustments=events)
        @test event_rows[1].wasserstein1 == 0
        # Both bars fit the bad grid, but its first wide bin spreads mass
        # below 8; the split would move that full histogram support below 4.
        @test_throws ArgumentError grid_convergence(event_bars,
            [PriceGrid([4,9,10]),valid_grid]; model=UniformModel(),adjustments=events)
        @test_throws ArgumentError grid_convergence([bar],PriceGrid[])
        @test_throws ArgumentError grid_convergence(DailyBar[],[coarse])
        @test_throws ArgumentError grid_convergence([bar],[PriceGrid([1.1,3]),coarse])
        @test_throws ArgumentError grid_convergence([bar],[coarse]; reference_grid=PriceGrid([1,2.9]))
        @test_throws ArgumentError grid_convergence([bar],[coarse]; initial=ChipDistribution(coarse,[1]))
        @test_throws ArgumentError grid_convergence([bar],[coarse]; grid=coarse)
        @test_throws ArgumentError grid_convergence([bar],[coarse]; quantiles=[NaN])
        @test_throws ArgumentError grid_convergence([bar],[coarse]; prices=[Inf])
        @test grid_convergence([bar],[coarse]; initial=nothing)[1].wasserstein1 == 0
        empty_points = grid_convergence([bar],[coarse]; quantiles=[],prices=[])
        @test isempty(empty_points[1].quantile_errors)
        @test isempty(empty_points[1].profit_errors)
    end

    @testset "Dated series preserve price-basis validation" begin
        series = BarSeries([Date(2026,1,5),Date(2026,1,6)],[bar,bar];
                           price_basis=:fixed_adjusted,turnover_basis=:float_shares)
        grids = [PriceGrid([0,1,3]),PriceGrid(collect(0:0.5:3))]
        rows = grid_convergence(series,grids; model=UniformModel())
        @test length(rows) == 2 && all(row -> row.wasserstein1 == 0,rows)
        @test_throws r"fixed-adjusted" grid_convergence(series,grids;
            adjustments=[PriceAdjustment(),PriceAdjustment(scale=0.75)])
    end
end
