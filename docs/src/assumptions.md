# Data and corporate-action assumptions

## Input responsibilities

The package does not download market data or invent stock samples. Included examples and tests use synthetic data. For a plain vector of `DailyBar` values, the caller must ensure a single security, chronological order and no duplicate observations. `BarSeries` rejects duplicate or unordered dates and retains security and research-basis metadata. `read_bars` imports simple unquoted files; see [Importing market data](data.md). The package does not infer trading calendars or detect future information in the input.

`DailyBar` requires only low, high, close and turnover; VWAP is optional. Open, volume, amount and tradable share counts must be retained and cleaned upstream. All prices must be finite and positive, and close/VWAP must lie in `[low,high]`. Missing values and suspension placeholders must not be presented as actual trades.

- Turnover is a fraction: `0.05` means 5%. Do not pass a provider's percentage value `5` directly. Use a consistent denominator: tradable float, free float and total shares are different bases. If the denominator has not been independently verified, explicitly record `turnover_basis=:provider_reported`; this does not assert any of those known share-count definitions. Inputs may exceed 1: the linear model saturates and the exponential model approaches 1.
- Empirical trade models accept finite nonnegative volumes in consistent units, such as shares or lots. Normalization uses relative weights only; total volume must be positive. Every trade price must lie within the bar's range.
- Do not manufacture VWAP from daily OHLC values. Before calculating it from amount/volume, verify currency and volume units, included trade types and statistical scope, then check the daily range.
- With an initial distribution and zero effective turnover, the state is unchanged after any cost adjustment has been applied. Suspensions may be omitted from the observation sequence; preserve calendar alignment upstream if needed. A zero-turnover first day without a prior still seeds the model and cannot be interpreted as recovered actual holdings.
- A provider's cost distribution can serve as `initial`, but its covered period must not also be processed again as updates. Record the prior's date and price basis.

## Price coordinates and events

Choose and record one of these workflows:

1. All historical inputs and the prior already share a fixed adjusted price basis. Use the default identity adjustments to avoid adjusting twice. If the chosen basis depends on future events, assess look-ahead information when backtesting.
2. Inputs use each day's contemporaneous prices. Supply explicit `PriceAdjustment(scale=s, shift=b)` values to map previous costs to `p'=s*p+b` on event days; that day's observations already use the new basis. Derive `s` and `b` from legitimate source data and a declared research definition, rather than inferring them from price gaps.

For a 2:1 split, `scale=0.5` illustrates the coordinate change. It transforms cost coordinates and probability mass only. Dividend cost treatment, rights subscriptions, bonus shares, changes in tradable float and mixtures of existing and new holdings need additional modelling. A single scale/shift cannot exactly represent all corporate actions, and this version does not track absolute share counts.

```julia
prior = ChipDistribution(PriceGrid([4, 5, 6, 8, 10, 12]), [0, 0, 0, 0, 1])
bar = DailyBar(low=5, high=5, close=5, turnover=0)
chips = chip_distribution([bar]; grid=prior.grid, initial=prior,
                          adjustments=[PriceAdjustment(scale=0.5)])
@assert average_cost(chips) ≈ average_cost(prior)/2
```

An affine transformation preserves the original bin's uniform density and distributes mass to target bins by overlap length. The target grid must cover all positive-mass support. Negative prices, numerical collapse and clipping are rejected. Repeated rebins introduce discretization error; assess grid convergence. With a prior, adjustment precedes turnover every day. Without a prior, the first day's adjustment must be identity.

## Compatibility and comparison

The package provides composable mathematical components and no unverified `TongDaXin` preset. Comparisons must fix the security, dates, initialization window, adjustment factors, turnover denominator, price precision, daily distribution and metric definitions. Compare the full CDF, cost quantiles and profit ratios separately. If a commercial algorithm is unpublished, report discrepancies on the specific data without claiming recovery of its implementation.

Callers must verify rights to use and redistribute market data and API outputs. The repository contains only synthetic data and does not embed third-party project code. A completed comparison against a public algorithm on real daily bars is described in the [experiment report](market_validation.md). Tongdaxin client acceptance, corporate-action validation and multi-source validation remain outstanding.
