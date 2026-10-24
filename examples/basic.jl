using AShareCostDistributions

grid = PriceGrid(collect(8.0:0.02:14.0))
bars = [
    DailyBar(low=9, high=11, close=10, turnover=0.05),
    DailyBar(low=9.5, high=12, close=11, turnover=0.12),
    DailyBar(low=10, high=12.5, close=12, turnover=0.08),
]
history = chip_history(bars; grid, model=TriangularModel(), turnover_model=LinearTurnover())
chips = chip_distribution(bars; grid)
@assert probabilities(chips) ≈ probabilities(history[end])
@assert sum(probabilities(chips)) ≈ 1
println("Synthetic example, not market observations")
println("Mean cost: ", average_cost(chips))
println("Profitable fraction at 12: ", profit_ratio(chips, 12))
println("Median cost: ", cost_quantile(chips, 0.5))
println("90% equal-tail concentration: ", concentration(chips))

# A split is an explicit coordinate change before today's replacement.
prior = ChipDistribution(PriceGrid([4, 5, 6, 8, 10, 12]), [0, 0, 0, 0, 1])
adjusted = chip_distribution([DailyBar(low=5,high=5,close=5,turnover=0)];
    grid=prior.grid, initial=prior, adjustments=[PriceAdjustment(scale=0.5)])
@assert average_cost(adjusted) ≈ average_cost(prior)/2
println("Split on an aligned grid: ", probabilities(adjusted))
