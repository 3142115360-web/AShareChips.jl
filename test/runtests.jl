using Test
using AShareChips
using Aqua

# A user's extensions rely only on the two documented dispatch hooks.
struct TestFixedDailyModel <: AbstractDailyModel end
AShareChips.daily_distribution(::TestFixedDailyModel, grid::PriceGrid, ::DailyBar) =
    ChipDistribution(grid, [0, 1])
struct TestHalfTurnover <: AbstractTurnoverModel end
AShareChips.effective_turnover(::TestHalfTurnover, ::Real) = 0.5
struct TestWrongGridDailyModel <: AbstractDailyModel end
AShareChips.daily_distribution(::TestWrongGridDailyModel, ::PriceGrid, ::DailyBar) =
    ChipDistribution(PriceGrid([8, 9, 12]), [0, 1])
struct TestInvalidTurnover <: AbstractTurnoverModel
    value::Float64
end
AShareChips.effective_turnover(model::TestInvalidTurnover, ::Real) = model.value

@testset "AShareChips" begin
    @testset "Validated grids, normalized masses, and owned snapshots" begin
        edges = [8.0, 10.0, 12.0, 14.0]
        grid = PriceGrid(edges)
        weights = [1.0, 2.0, 1.0]
        state = ChipDistribution(grid, weights)
        @test bin_edges(grid) == edges
        @test price_centers(grid) == [9.0, 11.0, 13.0]
        @test probabilities(state) ≈ [0.25, 0.5, 0.25]

        edges[1] = 0.0
        weights[1] = 100.0
        returned_edges = bin_edges(grid)
        returned_centers = price_centers(grid)
        returned_mass = probabilities(state)
        returned_edges[1] = 1.0
        returned_centers[1] = 1.0
        returned_mass[1] = 0.0
        @test bin_edges(grid) == [8.0, 10.0, 12.0, 14.0]
        @test price_centers(grid) == [9.0, 11.0, 13.0]
        @test probabilities(state) ≈ [0.25, 0.5, 0.25]
        @test bin_edges(PriceGrid([0, 1, 2])) == [0, 1, 2]

        for invalid in (Float64[], [1.0], [2.0, 1.0], [1.0, 1.0],
                        [-1.0, 1.0], [1.0, Inf], [1.0, NaN])
            @test_throws ArgumentError PriceGrid(invalid)
        end
        for invalid in ([1.0, 2.0], [0.0, 0.0, 0.0], [-1.0, 2.0, 1.0],
                        [NaN, 1.0, 1.0], [Inf, 1.0, 1.0])
            @test_throws ArgumentError ChipDistribution(grid, invalid)
        end
    end

    @testset "Daily inputs and turnover models" begin
        @test DailyBar(low=8, high=12, close=10, turnover=1.5) isa DailyBar
        @test DailyBar(low=10, high=10, close=10, turnover=0, vwap=10) isa DailyBar
        for kwargs in (
            (; low=0, high=12, close=10, turnover=0.2),
            (; low=12, high=8, close=10, turnover=0.2),
            (; low=8, high=12, close=7, turnover=0.2),
            (; low=8, high=12, close=13, turnover=0.2),
            (; low=8, high=12, close=10, turnover=-0.1),
            (; low=8, high=Inf, close=10, turnover=0.2),
            (; low=8, high=12, close=NaN, turnover=0.2),
            (; low=8, high=12, close=10, turnover=NaN),
            (; low=8, high=12, close=10, turnover=Inf),
            (; low=8, high=12, close=10, turnover=0.2, vwap=13),
            (; low=8, high=12, close=10, turnover=0.2, vwap=NaN),
        )
            @test_throws ArgumentError DailyBar(; kwargs...)
        end

        @test effective_turnover(LinearTurnover(), 0.0) == 0.0
        @test effective_turnover(LinearTurnover(), 0.2) ≈ 0.2
        @test effective_turnover(LinearTurnover(), 1.5) == 1.0
        @test effective_turnover(LinearTurnover(k=2), 0.3) ≈ 0.6
        @test effective_turnover(LinearTurnover(k=0), 0.9) == 0.0
        @test effective_turnover(ExponentialTurnover(), log(2)) ≈ 0.5
        @test effective_turnover(ExponentialTurnover(k=2), log(2)) ≈ 0.75
        @test effective_turnover(ExponentialTurnover(), 1000) == 1.0
        @test effective_turnover(ExponentialTurnover(k=0), 1000) == 0.0
        for model in (LinearTurnover(), ExponentialTurnover())
            for tau in (-0.1, NaN, Inf)
                @test_throws ArgumentError effective_turnover(model, tau)
            end
        end
        for k in (-1.0, NaN, Inf)
            @test_throws ArgumentError LinearTurnover(k=k)
            @test_throws ArgumentError ExponentialTurnover(k=k)
        end
        @test_throws ArgumentError TriangularModel(peak=:unsupported)
    end

    @testset "Exact uniform and triangular bin probabilities" begin
        grid = PriceGrid([8, 10, 12, 14])
        bar = DailyBar(low=9, high=13, close=11, turnover=0.2)
        @test probabilities(daily_distribution(UniformModel(), grid, bar)) ≈ [1 / 4, 1 / 2, 1 / 4]

        symmetric_grid = PriceGrid([8, 9, 10, 11, 12])
        symmetric_bar = DailyBar(low=8, high=12, close=10, turnover=0.2)
        symmetric = daily_distribution(TriangularModel(), symmetric_grid, symmetric_bar)
        @test probabilities(symmetric) ≈ [1 / 8, 3 / 8, 3 / 8, 1 / 8]

        left_peak = DailyBar(low=8, high=12, close=8, turnover=0.2)
        right_peak = DailyBar(low=8, high=12, close=12, turnover=0.2)
        @test probabilities(daily_distribution(TriangularModel(peak=:close), symmetric_grid, left_peak)) ≈
              [7 / 16, 5 / 16, 3 / 16, 1 / 16]
        @test probabilities(daily_distribution(TriangularModel(peak=:close), symmetric_grid, right_peak)) ≈
              [1 / 16, 3 / 16, 5 / 16, 7 / 16]

        typical_grid = PriceGrid([8, 10, 11, 12])
        @test probabilities(daily_distribution(TriangularModel(), typical_grid, right_peak)) ≈
              [3 / 8, 7 / 16, 3 / 16]
        @test probabilities(daily_distribution(TriangularModel(peak=:close), typical_grid, right_peak)) ≈
              [1 / 4, 5 / 16, 7 / 16]
        vwap_grid = PriceGrid([7, 8, 9, 10, 11, 12, 13])
        vwap_bar = DailyBar(low=8, high=12, close=10, turnover=0.2, vwap=9)
        @test probabilities(daily_distribution(TriangularModel(peak=:vwap), vwap_grid, vwap_bar)) ≈
              [0, 1 / 4, 5 / 12, 1 / 4, 1 / 12, 0]
        @test_throws ArgumentError daily_distribution(TriangularModel(peak=:vwap), grid, bar)

        for model in (UniformModel(), TriangularModel(), TriangularModel(peak=:close))
            for (price, expected) in ((8, [1, 0, 0]), (10, [0, 1, 0]), (14, [0, 0, 1]))
                point_bar = DailyBar(low=price, high=price, close=price, turnover=0)
                @test probabilities(daily_distribution(model, grid, point_bar)) == expected
            end
            @test_throws ArgumentError daily_distribution(
                model, grid, DailyBar(low=7, high=9, close=8, turnover=0.2))
            @test_throws ArgumentError daily_distribution(
                model, grid, DailyBar(low=13, high=15, close=14, turnover=0.2))
        end
    end

    @testset "Empirical volume weights and boundary allocation" begin
        grid = PriceGrid([8, 10, 12, 14])
        bar = DailyBar(low=8, high=14, close=10, turnover=0.2)
        prices = [8.0, 10.0, 10.0, 14.0]
        volumes = [1.0, 2.0, 3.0, 4.0]
        model = EmpiricalModel(prices, volumes)
        prices[1] = 100.0
        volumes[1] = 100.0
        @test probabilities(daily_distribution(model, grid, bar)) ≈ [0.1, 0.5, 0.4]
        @test probabilities(daily_distribution(EmpiricalModel([8, 14], [0, 4]), grid, bar)) == [0, 0, 1]
        for (prices, volumes) in (
            (Float64[], Float64[]), ([8, 10], [1]), ([8, 10], [0, 0]),
            ([8, 10], [1, -1]), ([8, 10], [1, NaN]), ([8, 10], [1, Inf]),
            ([8, NaN], [1, 1]), ([8, Inf], [1, 1]), ([0, 8], [1, 1]),
        )
            @test_throws ArgumentError EmpiricalModel(prices, volumes)
        end
        @test_throws ArgumentError daily_distribution(EmpiricalModel([7, 10], [1, 1]), grid, bar)
        @test_throws ArgumentError daily_distribution(EmpiricalModel([10, 15], [1, 1]), grid, bar)
        @test_throws ArgumentError daily_distribution(EmpiricalModel([8, 10], [1, 1]), grid,
            DailyBar(low=7, high=14, close=10, turnover=0.2))
    end

    @testset "Distribution statistics, gaps, and central concentration" begin
        grid = PriceGrid([8, 10, 12, 14])
        state = ChipDistribution(grid, [1, 0, 3])
        @test average_cost(state) ≈ 12.0
        for (price, expected) in ((7, 0), (8, 0), (9, 1 / 8), (10, 1 / 4),
                                  (11, 1 / 4), (12, 1 / 4), (13, 5 / 8),
                                  (14, 1), (15, 1))
            @test profit_ratio(state, price) ≈ expected
        end
        for (q, expected) in ((0, 8), (1 / 8, 9), (1 / 4, 10), (5 / 8, 13), (1, 14))
            @test cost_quantile(state, q) ≈ expected
        end
        @test cost_quantile(state, 0.2501) > 12
        interior = ChipDistribution(grid, [0, 1, 0])
        @test cost_quantile(interior, 0) == 10
        @test cost_quantile(interior, 0.5) == 11
        @test cost_quantile(interior, 1) == 12

        single = ChipDistribution(PriceGrid([8, 12]), [1])
        central = concentration(single)
        @test keys(central) == (:lower, :upper, :width, :relative_width)
        @test central.lower ≈ 8.2
        @test central.upper ≈ 11.8
        @test central.width ≈ 3.6
        @test central.relative_width ≈ 0.18
        whole = concentration(single; coverage=1)
        @test whole.lower == 8
        @test whole.upper == 12
        @test whole.width == 4
        @test whole.relative_width ≈ 0.2
        for q in (-0.01, 1.01, NaN, Inf)
            @test_throws ArgumentError cost_quantile(state, q)
        end
        for coverage in (0.0, -0.1, 1.1, NaN, Inf)
            @test_throws ArgumentError concentration(state; coverage=coverage)
        end
        for price in (NaN, Inf, -Inf)
            @test_throws ArgumentError profit_ratio(state, price)
        end
        subnormal = ChipDistribution(PriceGrid([0, nextfloat(0.0)]), [1])
        @test_throws ArgumentError concentration(subnormal; coverage=nextfloat(0.0))
    end

    @testset "Nonmutating recursive updates and closed-form survival" begin
        grid = PriceGrid([8, 10, 12, 14])
        initial = ChipDistribution(grid, [1, 0, 0])
        daily = ChipDistribution(PriceGrid([8, 10, 12, 14]), [0, 1, 0])
        result = update_chips(initial, daily, 0.25)
        @test probabilities(result) ≈ [0.75, 0.25, 0]
        @test probabilities(initial) == [1, 0, 0]
        @test probabilities(daily) == [0, 1, 0]
        @test probabilities(update_chips(initial, daily, 0)) == [1, 0, 0]
        @test probabilities(update_chips(initial, daily, 1)) == [0, 1, 0]
        result = initial
        for _ in 1:5
            result = update_chips(result, daily, 0.2)
        end
        @test probabilities(result) ≈ [(4 / 5)^5, 1 - (4 / 5)^5, 0]
        @test probabilities(initial) == [1, 0, 0]
        mismatch = ChipDistribution(PriceGrid([8, 9, 12, 14]), [1, 0, 0])
        @test_throws ArgumentError update_chips(initial, mismatch, 0.5)
        for alpha in (-0.1, 1.1, NaN, Inf)
            @test_throws ArgumentError update_chips(initial, daily, alpha)
        end
    end

    @testset "History seeding, daily model choices, and causality" begin
        grid = PriceGrid([8, 10, 12])
        bars = [
            DailyBar(low=9, high=9, close=9, turnover=0),
            DailyBar(low=11, high=11, close=11, turnover=0.25),
            DailyBar(low=9, high=9, close=9, turnover=0.5),
        ]
        history = chip_history(bars; grid=grid)
        @test length(history) == 3
        @test probabilities(history[1]) == [1, 0]
        @test probabilities(history[2]) ≈ [0.75, 0.25]
        @test probabilities(history[3]) ≈ [0.875, 0.125]
        @test probabilities(chip_distribution(bars; grid=grid)) ≈ probabilities(history[end])
        prefix = chip_history(bars[1:2]; grid=grid)
        @test probabilities(prefix[1]) == probabilities(history[1])
        @test probabilities(prefix[2]) == probabilities(history[2])

        initial = ChipDistribution(grid, [0, 1])
        seeded = chip_history(bars; grid=grid, initial=initial)
        @test probabilities(seeded[1]) == [0, 1]
        @test probabilities(seeded[2]) == [0, 1]
        @test probabilities(seeded[3]) ≈ [0.5, 0.5]
        @test probabilities(initial) == [0, 1]
        rate_bars = [
            DailyBar(low=8, high=12, close=8, turnover=0.25),
            DailyBar(low=8, high=12, close=12, turnover=0.5),
        ]
        models = [UniformModel(), TriangularModel(peak=:close)]
        varying = chip_history(rate_bars; grid=grid, model=models)
        @test probabilities(varying[1]) ≈ [0.5, 0.5]
        @test probabilities(varying[2]) ≈ [0.375, 0.625]
        prior = ChipDistribution(grid, [1, 0])
        varying_prior = chip_history(rate_bars; grid=grid, model=models, initial=prior)
        @test probabilities(varying_prior[1]) ≈ [0.875, 0.125]
        @test probabilities(varying_prior[2]) ≈ [0.5625, 0.4375]

        exponential_bars = [bars[1], DailyBar(low=11, high=11, close=11, turnover=log(2))]
        @test probabilities(chip_distribution(exponential_bars; grid=grid,
            turnover_model=ExponentialTurnover())) ≈ [0.5, 0.5]
        @test_throws ArgumentError chip_history(DailyBar[]; grid=grid)
        @test_throws ArgumentError chip_distribution(DailyBar[]; grid=grid)
        @test_throws ArgumentError chip_history(bars; grid=grid, model=[UniformModel()])
        @test_throws ArgumentError chip_history(bars; grid=grid,
            initial=ChipDistribution(PriceGrid([8, 9, 12]), [1, 0]))
    end

    @testset "Affine cost rebasing conserves mass without clipping" begin
        source = ChipDistribution(PriceGrid([8, 10, 12]), [1, 1])
        half = rebase(source, PriceAdjustment(scale=0.5); grid=PriceGrid([4, 5, 6]))
        @test probabilities(half) ≈ [0.5, 0.5]
        @test average_cost(half) ≈ average_cost(source) / 2
        @test probabilities(source) ≈ [0.5, 0.5]
        @test bin_edges(source.grid) == [8, 10, 12]

        single = ChipDistribution(PriceGrid([2, 4]), [1])
        shifted = rebase(single, PriceAdjustment(shift=1); grid=PriceGrid([3, 3.5, 4.5, 5]))
        @test probabilities(shifted) ≈ [0.25, 0.5, 0.25]
        expanded = rebase(single, PriceAdjustment(scale=2, shift=1); grid=PriceGrid([5, 6, 8, 9]))
        @test probabilities(expanded) ≈ [0.25, 0.5, 0.25]
        @test sum(probabilities(expanded)) ≈ 1
        @test probabilities(rebase(source, PriceAdjustment())) ≈ probabilities(source)

        sparse = ChipDistribution(PriceGrid([2, 3, 4, 6, 8]), [0, 0, 0, 1])
        @test probabilities(rebase(sparse, PriceAdjustment(scale=0.5))) ≈ [0, 1, 0, 0]
        @test_throws ArgumentError rebase(single, PriceAdjustment(); grid=PriceGrid([2.1, 4]))
        @test_throws ArgumentError rebase(single, PriceAdjustment(); grid=PriceGrid([2, 3.9]))
        @test_throws ArgumentError rebase(single, PriceAdjustment(shift=-3))
        for scale in (0.0, -1.0, NaN, Inf)
            @test_throws ArgumentError PriceAdjustment(scale=scale)
        end
        for shift in (NaN, Inf, -Inf)
            @test_throws ArgumentError PriceAdjustment(shift=shift)
        end
        # An overflowing intermediate product still has a finite affine result.
        wide = ChipDistribution(PriceGrid([8e307, 1e308]), [1])
        mapped_edges = [fma(2.0, 8e307, -1e308), fma(2.0, 1e308, -1e308)]
        cancellation = rebase(wide, PriceAdjustment(scale=2, shift=-1e308);
            grid=PriceGrid(mapped_edges))
        @test probabilities(cancellation) == [1]
        @test isfinite(average_cost(cancellation))
        @test average_cost(cancellation) ≈ 8e307
    end

    @testset "Per-day adjustments precede turnover updates" begin
        grid = PriceGrid([4, 5, 6, 8, 10, 12])
        initial = ChipDistribution(grid, [0, 0, 0, 1, 0])
        bars = [
            DailyBar(low=9, high=9, close=9, turnover=0),
            DailyBar(low=11, high=11, close=11, turnover=0.25),
        ]
        adjustments = [PriceAdjustment(scale=0.5), PriceAdjustment(shift=1)]
        history = chip_history(bars; grid=grid, initial=initial, adjustments=adjustments)
        @test probabilities(history[1]) ≈ [1, 0, 0, 0, 0]
        @test probabilities(history[2]) ≈ [0, 0.75, 0, 0, 0.25]
        @test probabilities(initial) == [0, 0, 0, 1, 0]
        @test_throws ArgumentError chip_history(bars; grid=grid, adjustments=adjustments)
        @test_throws ArgumentError chip_history(bars; grid=grid,
            initial=initial, adjustments=[PriceAdjustment()])

        unseeded_bars = [
            DailyBar(low=8, high=10, close=9, turnover=0),
            DailyBar(low=4, high=5, close=4.5, turnover=0),
        ]
        unseeded_history = chip_history(unseeded_bars; grid=grid, model=UniformModel(),
            adjustments=[PriceAdjustment(), PriceAdjustment(scale=0.5)])
        @test probabilities(unseeded_history[1]) ≈ [0, 0, 0, 1, 0]
        @test probabilities(unseeded_history[2]) ≈ [1, 0, 0, 0, 0]
    end

    @testset "Deterministic distribution and inverse-CDF invariants" begin
        grid = PriceGrid([1, 2, 3, 4, 5, 6, 7])
        for bar in (
            DailyBar(low=1, high=7, close=1, turnover=0.1),
            DailyBar(low=1.25, high=6.75, close=4, turnover=0.2),
            DailyBar(low=2, high=5, close=5, turnover=2),
        ), model in (UniformModel(), TriangularModel(), TriangularModel(peak=:close))
            state = daily_distribution(model, grid, bar)
            mass = probabilities(state)
            @test all(isfinite, mass)
            @test all(>=(0), mass)
            @test sum(mass) ≈ 1 atol=1e-14
            prices = collect(range(0.5, 7.5; length=57))
            cdf = [profit_ratio(state, price) for price in prices]
            @test issorted(cdf)
            @test first(cdf) == 0
            @test last(cdf) == 1
            quantiles = [cost_quantile(state, q) for q in (0.1, 0.25, 0.5, 0.75, 0.9)]
            @test issorted(quantiles)
            for (q, price) in zip((0.1, 0.25, 0.5, 0.75, 0.9), quantiles)
                @test profit_ratio(state, price) ≈ q atol=1e-12
            end
        end
    end

    @testset "Numerical scaling and documented extension dispatch" begin
        grid = PriceGrid([8, 10, 12])
        @test probabilities(ChipDistribution(grid, [floatmax(Float64), floatmax(Float64)])) ≈ [0.5, 0.5]
        @test probabilities(ChipDistribution(grid, [1e-300, 3e-300])) ≈ [0.25, 0.75]
        bar = DailyBar(low=8, high=12, close=10, turnover=0)
        large_volume = EmpiricalModel([9, 11], [floatmax(Float64), floatmax(Float64)])
        @test probabilities(daily_distribution(large_volume, grid, bar)) ≈ [0.5, 0.5]
        prior = ChipDistribution(grid, [1, 0])
        @test probabilities(chip_distribution([bar]; grid=grid, initial=prior,
            model=TestFixedDailyModel(), turnover_model=TestHalfTurnover())) ≈ [0.5, 0.5]
        @test probabilities(prior) == [1, 0]
        @test_throws ArgumentError chip_history([bar]; grid=grid, model=TestWrongGridDailyModel())
        # The first unseeded day must validate custom turnover even though it seeds D1.
        for alpha in (NaN, -0.1, 1.1)
            @test_throws ArgumentError chip_distribution([bar]; grid=grid,
                turnover_model=TestInvalidTurnover(alpha))
        end

        extreme = ChipDistribution(PriceGrid([1e308, 1.6e308]), [1])
        @test isfinite(average_cost(extreme))
        @test average_cost(extreme) ≈ 1.3e308
        whole = concentration(extreme; coverage=1)
        @test isfinite(whole.relative_width)
        @test whole.relative_width ≈ 3 / 13
    end
end

include("engine_inputs.jl")
include("data.jl")
include("validation.jl")
include("reference.jl")
include("adjustments.jl")
include("history_comparison.jl")
include("cli.jl")
include("review_regressions.jl")

@testset "Aqua package quality" begin
    Aqua.test_all(AShareChips; undocumented_names=true)
end
