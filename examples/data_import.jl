using AShareCostDistributions
using Dates

# Every value and date in this fixture is synthetic, not a market observation.
# The SYNTHETIC suffix explicitly avoids claiming an exchange-listed security.
fixture = joinpath(@__DIR__, "fixtures", "daily_synthetic.csv")
series = read_bars(fixture; price_basis=:unadjusted, turnover_basis=:float_shares,
                   turnover_unit=:percent)
grid = PriceGrid(collect(8.0:0.02:14.0))
history = dated_history(series; grid, model=TriangularModel())
chips = chip_distribution(series; grid)
@assert probabilities(chips) ≈ probabilities(history[end].distribution)
@assert trade_dates(series) == [Date(2000, 1, 3), Date(2000, 1, 4), Date(2000, 1, 5)]
@assert series.bars[1].turnover == 0.05
@assert series.bars[2].vwap === nothing
println("Synthetic observations for ", series.symbol, "; no market-data claims")
for snapshot in history
    println(snapshot.date, ": estimated average cost = ", average_cost(snapshot.distribution))
end

# Required metadata is also explicit when data has been parsed upstream.
# Already adjusted bars may use only identity adjustments.
fixed = BarSeries(trade_dates(series), series.bars; symbol=series.symbol,
                  price_basis=:fixed_adjusted, turnover_basis=:float_shares)
@assert probabilities(chip_distribution(fixed; grid)) ≈ probabilities(chips)
