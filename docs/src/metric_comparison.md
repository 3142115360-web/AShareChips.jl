# Comparing external cost and profit metrics

Some sources provide only daily mean cost, a few cost quantiles or profit ratios at particular prices. These can be compared directly with the model, but cannot determine a full cost distribution. `compare_metrics` accepts such scalar references without inventing a histogram. It does not return Wasserstein distance, full-distribution maximum CDF error or a software-compatibility conclusion.

```julia
using AShareCostDistributions

estimate = ChipDistribution(PriceGrid([8, 10, 12]), [1, 1])
comparison = compare_metrics(estimate; mean_cost=10.25,
    quantiles=[0.5], quantile_costs=[10.0],
    prices=[10.0], profit_ratios=[40.0], profit_unit=:percent)
@assert comparison.mean_cost_error == -0.25
@assert comparison.quantile_errors == [0.0]
@assert comparison.profit_errors ≈ [0.1]
```

All errors are model estimate minus reference. Costs and cost errors use price units. Profit ratios and their errors use fractions from 0 to 1; an error of `0.01` is one percentage point. Only explicitly supplied metrics are compared. Without a mean reference, all three `mean_cost_*` results are `nothing`. Quantiles and costs, and evaluation prices and profit ratios, must be supplied in pairs. At least one metric is required.

## File workflow

Run the bundled synthetic example:

```sh
julia --project=. examples/compare_metrics_csv.jl examples/metrics-analysis.toml
```

Dates, identifiers, prices and metrics in `examples/fixtures/metrics_synthetic.csv` are hand-constructed synthetic data, also identified by the `provenance` column. The first day's mean, median and profit ratio at price 10 can be derived by hand from a symmetric triangle. The second reference day deliberately provides approximate values to illustrate errors, without claiming agreement with any software.

The script uses the same top-level market-data settings, `grid`, `model` daily/turnover settings and optional `events` file as `analyze_csv.jl`. It simulates the complete input history once; days without reference data still update the historical distribution. Reference settings are:

```toml
[reference]
input = "reference.csv"
price_basis = "unadjusted"
profit_unit = "fraction"
matching = "intersection"
quantiles = [0.05, 0.15, 0.5, 0.85, 0.95]
quantile_columns = ["cost_q05", "cost_q15", "cost_q50", "cost_q85", "cost_q95"]

[reference.columns]
date = "date"
symbol = "symbol"
profit_price = "profit_price"
profit_ratio = "profit_fraction"
# Only add this mapping when the supplied field really is a mean.
# mean_cost = "weighted_mean"
```

`date` and `symbol` default to same-named columns. Other metrics must be explicitly mapped; their meaning is not guessed from headers. `quantiles` must be unique values in 0 to 1, mapped one-to-one to `quantile_columns` in configuration order. Means, quantile costs and evaluation prices in the file must be finite and nonnegative; quantile costs must be nondecreasing with quantile level. Individual metric cells may be blank, but each row needs at least one metric. A profit price and ratio must either both be supplied or both be blank. The core `compare_metrics` API also accepts finite negative evaluation prices; this A-share file workflow applies the narrower nonnegative requirement.

`profit_unit` is required as `fraction` or `percent`, even for cost-only files. Valid ranges are `[0,1]` and `[0,100]` respectively; percentages are divided by 100 exactly once. Out-of-range values, nonfinite values, nonzero inputs that convert to Float64 zero, and underflow during percentage conversion are rejected. The value 0.5 could mean 50% or 0.5%; values alone cannot reveal a false unit declaration. Researchers must verify source units, since the script does not guess.

Dates must exactly match `yyyy-mm-dd` by default. Explicit formats such as `reference.dateformat = "yyyymmdd"` are supported. Dates must increase strictly; duplicates, truncated dates and automatic sorting are not allowed. Security identifiers retain leading zeroes and suffixes. Each reference row must have a nonempty, consistent identifier, or one must be explicitly declared through `reference.symbol` or top-level `symbol`. Both market-data and reference identifiers must be known and match. The script does not silently label an anonymous, undeclared reference file with the market-data security.

Market data and references must declare the same `price_basis`. This is necessary but insufficient: identical `fixed_adjusted` labels do not prove identical adjustment coordinates, and unadjusted data still require consistent corporate-action treatment. Event files follow the adjustment-before-turnover rule described in [Adjustment events](adjustments.md); fixed-adjusted bars reject nonidentity mappings. End-of-day reference metrics may become available after the close, so a comparison date does not establish backtest availability time.

`matching = "strict"` requires identical dates. `intersection` outputs only common dates. The return value and console report `estimate_only_dates` and `reference_only_dates` for the unmatched dates on either side. No observations are fabricated and no recurrence history is removed. No common dates is an error. Even unmatched reference rows are validated for security, units, dates, numbers and quantile ordering; filtering dates cannot bypass invalid input.

Reference input is simple unquoted UTF-8 CSV. A first-line BOM, CRLF, blank lines and surrounding cell whitespace are accepted. Empty or duplicate headers, inconsistent column counts, invalid UTF-8 and double quotes in any column are rejected. Extra columns may retain provenance hashes or other records and are ignored by the parser. Convert complex CSV upstream with a full parser. The script does not retrieve data online.

The long-form output header is:

```text
date,symbol,metric,quantile,price,estimate,reference,error
```

`metric` is `mean_cost`, `cost_quantile` or `profit_ratio`; inapplicable `quantile` and `price` cells are blank. All inputs, configuration and results are validated before publishing the report. Existing files, directories and links are never overwritten. The return value also includes `output` and per-metric `rows` for further analysis.

## Map upstream fields by definition

The [official Tushare `cyq_perf` documentation](https://tushare.pro/document/2?doc_id=293) identifies `cost_5pct`, `cost_15pct`, `cost_50pct`, `cost_85pct` and `cost_95pct` as corresponding quantile costs, and `weight_avg` as weighted mean cost. Map them to quantiles `0.05/0.15/0.5/0.85/0.95` and optional `mean_cost` respectively. Map `ts_code` as the security and `trade_date` as the date, declaring `yyyymmdd`. `winner_rate` also needs its actual evaluation price. Verify its unit, price basis and update timing first; the script never assumes that its evaluation price equals a particular file's close.

In the [pinned AKShare `stock_cyq_em` implementation](https://github.com/akfamily/akshare/blob/fe10d1decb705e5f43cc8ca3339ca39e580fb8f4/akshare/stock_feature/stock_cyq_em.py), `avgCost` is calculated as the discrete cost at 50% cumulative mass, then exposed under a column labelled “average cost.” Map it as a `quantiles = [0.5]` reference, not as this package's mean. Its `benefitPart` is a fraction evaluated at the specified close; provide that price alongside it. Preserve the source version, window, grid, rounding and boundary conventions with the experiment. A field name alone does not establish matching definitions.

These mappings rely on public documentation and implementation, not Tongdaxin's private algorithm. Real experiments should also record original sources, retrieval times, file hashes, parameters, coverage, initialization, adjustments and discrepancies. Numerical proximity does not prove actual account holdings or exact software reproduction.

See the [real daily-bar comparison report](market_validation.md) for the completed independent algorithm experiment.
