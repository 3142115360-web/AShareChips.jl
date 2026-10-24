# Comparison errors and grid sensitivity

`compare_distributions` compares two cost histograms with explicit bin edges. `grid_convergence` changes the price grid under the same observations and model assumptions, reporting errors against a specified reference grid. Neither function fits parameters or downloads data. All runnable examples below are synthetic; comparisons with real data, providers and Tongdaxin require separately executed experiments.

## Distribution comparison

Each bin's mass is spread uniformly between its edges, giving a continuous, piecewise-linear CDF. The two distributions may have different edges, supports and bin counts. Comparison preserves each histogram's own interpretation without first rebinning either onto the other.

```julia
using AShareCostDistributions

reference = ChipDistribution(PriceGrid([1, 3]), [1])
estimate = ChipDistribution(PriceGrid([1.75, 3.75]), [1])
comparison = compare_distributions(estimate, reference;
                                   quantiles=[0, 0.1, 0.5, 0.9, 1],
                                   prices=[1.5, 2.0, 3.0])
@assert comparison.wasserstein1 ≈ 0.75
@assert comparison.max_cdf_error ≈ 0.375
@assert comparison.mean_cost_error ≈ 0.75
```

Write the estimate and reference CDFs as `F_est` and `F_ref`, and their quantile functions as `Q_est` and `Q_ref`. Every signed error is estimate minus reference.

| Returned field | Definition and units |
|---|---|
| `max_cdf_error` | `max(abs(F_est(p)-F_ref(p)))` across all prices; a probability fraction in `[0,1]`. For example, `0.02` means 2 percentage points. |
| `wasserstein1` | One-dimensional Wasserstein distance `∫ abs(F_est(p)-F_ref(p)) dp`; nonnegative and in price units. Both distributions must use the same currency and price basis. |
| `mean_cost_error` | Mathematically the difference in means; computed internally by stable CDF-difference integration to avoid subtracting large, nearly equal means. In price units. |
| `quantiles`, `quantile_errors` | A copy of caller-supplied q values and corresponding `Q_est(q)-Q_ref(q)` errors, in price units. |
| `prices`, `profit_errors` | Copies of evaluation prices and corresponding `F_est(p)-F_ref(p)` errors, as probability fractions. Default prices are all reference-bin midpoints, including zero-mass bins. |
| `comparison_points` | The sorted, unique union of both sets of bin edges, used for the full CDF comparison and distance integration. |

The CDF difference is linear between consecutive union edges, so the largest absolute difference occurs at an endpoint. Thus `max_cdf_error` covers the entire represented histogram rather than a sparse price sample. Wasserstein distance integrates each segment; if the difference crosses zero inside a segment, the two triangular areas are calculated separately. These calculations remain subject to Float64 rounding and cannot remove discretization error already present in the input histograms.

Quantiles must be finite values in `[0,1]`; `q=0/1` refers to positive-mass support endpoints. At a CDF plateau, the leftmost inverse convention of `cost_quantile` applies. Prices must be finite and may lie outside both supports. Quantile and price lists preserve input order and may contain duplicates or be empty; duplicate points produce duplicate errors. Returned vectors are independent copies; changing them does not change the input distributions. Swapping arguments leaves the two nonnegative distance metrics unchanged and reverses signed errors. Supply the same explicit `prices` when checking this for profit errors, because default prices come from the second argument.

## Grid sensitivity

```julia
using AShareCostDistributions

bars = [DailyBar(low=1, high=3, close=2, turnover=0.2)]
grids = [PriceGrid([1, 3]),
         PriceGrid(collect(1:0.5:3)),
         PriceGrid(collect(1:0.25:3))]
rows = grid_convergence(bars, grids; model=TriangularModel())
@assert [r.bin_count for r in rows] == [1, 4, 8]
@assert [r.max_cdf_error for r in rows] ≈ [1/8, 1/32, 0]
@assert [r.wasserstein1 for r in rows] ≈ [5/32, 1/32, 0]
```

Returned rows follow the order of `grids`. Each contains `bin_count`, `max_bin_width` and every distribution-comparison field. The last grid is the default reference, so choose the order deliberately. Supply `reference_grid=another_grid` for an additional reference that need not appear in `grids`. A simulation with edges identical to the reference is reused, producing exactly zero self-distances and signed errors. By default every row uses the same reference-grid midpoints for profit comparison.

An empty grid list is an error. `BarSeries` inputs retain their price-basis checks, including rejection of nonidentity adjustments for fixed-adjusted prices. Other observation and adjustment iterators are consumed once and reused across grids. Other `chip_distribution` keywords pass through, including daily models, turnover models and corporate-action mappings. Every grid must cover all daily ranges and all transformed positive-mass support. Coarse bins can extend support beyond a day's actual range, and later adjustments must also fit those occupied bin extensions; checking only actual low/high prices is insufficient.

Only `initial=nothing` is accepted. Automatically rebinning one prior onto each grid would also change initialization and mix prior error into the comparison. Studies needing a prior must explicitly prepare one on each grid, run `chip_distribution` separately, and compare using `compare_distributions`.

Zero error for the final grid only means the reference equals itself. A fine grid is a discretization reference, not actual holdings. Finer grids do not guarantee monotone errors for all models, arbitrary grid orders or repeated adjustment/rebinning. The decrease above is an analytical test result for a known triangular model. Report grid edges, maximum widths, supports, reference choice and all errors; assess stability over several fine grids.

## Real-data and provider comparison conventions

The repository does not supply real provider cost-distribution samples or claim Tongdaxin acceptance. The following is a suggested CSV exchange convention for future comparisons. [`read_bars`](data.md) imports simple unquoted delimited observations into `BarSeries`, with column mapping and fraction/percentage turnover conversion. General CSV with quoting, multiline fields or escapes requires upstream parsing. Import reference histograms with [`read_distributions`](reference.md) and align event tables with [`read_adjustments`](adjustments.md). Authorization, provenance checks and cleaning remain upstream responsibilities.

For daily observations, use one row per security and trading day. Suggested headers:

```csv
security,date,low,high,close,turnover,vwap,adjustment_scale,adjustment_shift,price_basis,turnover_basis,source,source_version
```

Use ISO dates, declare the exchange calendar and provide ascending, deduplicated observations for each security. In this exchange convention, `turnover` is a fraction, while `turnover_basis` records the denominator, such as tradable float, free float or total shares. Map `security` to symbol through `read_bars`'s `columns` keyword. Supply basis declarations as keywords and retain source/basis columns separately. Leave missing VWAP blank and construct it as `nothing`; do not infer it from daily OHLC. `adjustment_scale/shift` maps historical costs before that day's update. `read_bars` does not parse these two columns automatically: construct and pass `PriceAdjustment` values upstream. With a fixed adjusted basis, both values must represent identity to avoid double adjustment. The same `price_basis` must apply to observations, prior, reference distributions and evaluation prices.

For reference histograms, use one row per date and contiguous bin. Suggested headers:

```csv
security,date,bin_left,bin_right,mass,price_basis,source,source_version
```

Edges must be finite, nonnegative and strictly increasing, with each `bin_right` equal to the following `bin_left`. Fill support gaps with zero-mass bins. `mass` is probability mass, not density, volume or a percentage in this convention. Check nonnegativity, a positive total and normalization error upstream before constructing objects. Constructors normalize weights, so check source units first to prevent normalization from hiding unit errors. If a source provides only point prices and quantities, explicitly define boundaries, precision and binning assumptions in the research protocol; a point without a declared width is not a continuous histogram bin.

Separately record retrieval time, source page/API and version, permitted usage, missing-day handling, first-day seed or prior date and source, historical window, adjustment-factor provenance, model parameters and metric definitions. Record and skip missing reference dates; do not synthesize provider values. If Tongdaxin or another source supplies only profit ratios or cost quantiles, compare those explicitly defined metrics directly. Sparse summaries do not justify fabricating a full distribution and claiming a CDF comparison.

Error reports must distinguish numerical error in this package's histogram from differences against a provider's conventions on particular data and settings. Even close numerical agreement does not prove actual account costs, recover unpublished Tongdaxin internals or establish a trading strategy's effectiveness.

When positive masses smaller than machine epsilon are present, comparison uses internal exact rational normalization and integration, then converts results to Float64. See the [file comparison workflow](workflow.md) for combined daily-bar, histogram and event inputs.
