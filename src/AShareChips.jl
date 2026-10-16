module AShareChips

using Dates: Date, DateFormat, @dateformat_str
import Dates

export PriceGrid, ChipDistribution, DailyBar, AbstractDailyModel,
       UniformModel, TriangularModel, EmpiricalModel, daily_distribution,
       AbstractTurnoverModel, LinearTurnover, ExponentialTurnover, effective_turnover,
       PriceAdjustment, rebase, update_chips, chip_distribution, chip_history,
       bin_edges, price_centers, probabilities, average_cost, profit_ratio,
       cost_quantile, concentration,
       BarSeries, trade_dates, read_bars, dated_history,
       compare_distributions, grid_convergence,
       ReferenceSeries, read_distributions, read_adjustments, compare_history

include("types.jl")
include("models.jl")
include("engine.jl")
include("metrics.jl")
include("data.jl")
include("reference.jl")
include("adjustments.jl")
include("validation.jl")
include("history_comparison.jl")

end
