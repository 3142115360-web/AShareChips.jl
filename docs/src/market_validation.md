# Independent comparison on public daily-market data

This experiment was run on 2026-10-17 (Asia/Shanghai). It compares two research models on real daily bars. It is not a validation against Tongdaxin, and no account-level holding data were available.

## Input and provenance

A public Eastmoney request returned 242 unadjusted daily bars for `000001.SZ` in 2024. Both models received the final 210 observations, from 2024-02-23 through 2024-12-31. The reference was the JavaScript calculator in the pinned [AKShare implementation](https://github.com/akfamily/akshare/blob/fe10d1decb705e5f43cc8ca3339ca39e580fb8f4/akshare/stock_feature/stock_cyq_em.py). It produced five cost quantiles and a profitable-holder fraction for the final 90 dates, from 2024-08-19 through 2024-12-31.

The daily-field definitions are documented by [AKShare](https://akshare.akfamily.xyz/data/stock/stock.html), and the reader implementation was pinned at the same [source revision](https://github.com/akfamily/akshare/blob/fe10d1decb705e5f43cc8ca3339ca39e580fb8f4/akshare/stock_feature/stock_hist_em.py). Volume is reported in lots, amount in yuan, and turnover in percent. This experiment did not derive a synthetic VWAP from volume and amount. Because the turnover denominator was not independently verified, it was recorded as `turnover_basis=:provider_reported`.

Both sides used unadjusted prices and no corporate-action events. The sample may include dividend events, so the experiment does not validate cross-event cost accounting. Raw market data and per-date reference output are not redistributed because their redistribution terms were not established; the package and test fixtures contain only synthetic data.

## Deliberately different model definitions

AShareCostDistributions used its default triangular peak `(low+high+close)/3`, `LinearTurnover(k=1)`, a full first-day seed, and a fixed equal-width histogram. The 120 dates before the comparison window still contributed to its recurrence.

The pinned reference uses the four-price OHLC average as its peak, recomputes the historical price range for every date, uses 150 discrete points with a minimum one-cent interval, rounds displayed values to cents, and starts with no historical mass. Its field named `avgCost` is the discrete cost at cumulative mass 50%, so it was compared with `Q(0.5)`, not with this package's mathematical mean.

Initialization, peak, grid, and CDF-boundary rules therefore differ. The experiment measures their combined result; it does not attribute the difference to one component.

## Results

All 210 daily bars entered the simulation. Ninety dates had reference values, producing 540 scalar comparisons. Errors are estimate minus reference. With a 0.01-yuan grid:

| Metric | Mean absolute error | Maximum absolute error |
|:---|---:|---:|
| Q(0.05) cost | CNY 0.047842 | CNY 0.065451 |
| Q(0.15) cost | CNY 0.102102 | CNY 0.133089 |
| Q(0.50) cost | CNY 0.311007 | CNY 0.503976 |
| Q(0.85) cost | CNY 0.118015 | CNY 0.443710 |
| Q(0.95) cost | CNY 0.098673 | CNY 0.333149 |
| Profit fraction at the daily close | 7.4154 percentage points | 23.6430 percentage points |

These are differences between two estimated models, not errors relative to true holdings. No compatibility threshold was chosen. Sparse scalar metrics do not determine a full distribution, so full-CDF and Wasserstein errors are not reported.

## Grid sensitivity

| Grid step | Q(0.50) mean absolute error | Profit-fraction mean absolute error |
|:---|---:|---:|
| CNY 0.10 | CNY 0.305801 | 7.3834 percentage points |
| CNY 0.02 | CNY 0.310826 | 7.4138 percentage points |
| CNY 0.01 | CNY 0.311007 | 7.4154 percentage points |

The 0.02- and 0.01-yuan summaries are close, while a material model difference remains. This sample does not support the claim that grid refinement alone reproduces the reference. Controlled experiments would be needed to isolate initialization, daily peak, and discretization effects, followed by a licensed, versioned Tongdaxin export for any terminal-specific validation.

The [metric comparison workflow](metric_comparison.md) accepts legally obtained cost and profit summaries. Its analytical fixtures test the numerical contract; this experiment demonstrates actual differences between two public model definitions. Neither establishes trading effectiveness.
