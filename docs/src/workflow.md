# From files to a comparison report

The repository's `examples/analysis.toml` configures a daily market-data file, price grid and model, with optional reference histogram and corporate-action event files. All bundled examples are synthetic and make no real-stock or commercial-terminal acceptance claim.

```sh
julia --project=. examples/analyze_csv.jl examples/analysis.toml
```

This produces a three-day cost table and an error table against two days of hand-constructed reference histograms. The third day, which has no reference, is explicitly reported and still participates in the recurrence. The example deliberately retains differences between the model and hand-constructed reference. Choose different output filenames before repeating the run.

## Configuration

File paths are relative to the configuration file's directory. The price grid must cover all trading ranges and all positive-mass support after historical cost transformations.

```toml
input = "fixtures/daily_synthetic.csv"
output = "analysis-result.csv"
turnover_unit = "percent"
price_basis = "unadjusted"
turnover_basis = "float_shares"
# events = "my_verified_events.csv"  # Optional; verify against this input.

[grid]
lower = 8.0
upper = 14.0
step = 0.02

[model]
kind = "triangular"                 # Or uniform.
peak = "typical"                    # triangular also accepts close / vwap.
turnover_model = "linear"           # Or exponential.
turnover_k = 1.0

[comparison]
input = "fixtures/reference_synthetic.csv"
output = "comparison-result.csv"
price_basis = "unadjusted"
mass_unit = "fraction"              # Or percent / explicit weights.
matching = "intersection"           # strict requires identical date sets.
```

Events are not inferred from price gaps. `:fixed_adjusted` inputs reject nonidentity events. A nonidentity first-day event needs a prior; this example script has no prior configuration, so it cannot use such an event. The library API supports explicit priors. The bundled event sample is independently synthetic and must not be applied to unverified market data.

## Programmatic interface

```julia
using AShareCostDistributions, Dates

series = read_bars("examples/fixtures/daily_synthetic.csv";
    price_basis=:unadjusted, turnover_basis=:float_shares, turnover_unit=:percent)
reference = read_distributions("examples/fixtures/reference_synthetic.csv";
    price_basis=:unadjusted, mass_unit=:fraction)
result = compare_history(series, reference;
    grid=PriceGrid(collect(8:0.02:14)), matching=:intersection)
@assert result.estimate_only_dates == [Date(2000, 1, 5)]
```

By default, both market data and reference security identifiers must be known and identical. Known mismatches are always rejected. For caller-owned anonymous data, explicitly setting `require_symbol_match=false` accepts responsibility for the association. Price-basis labels must match, but labels do not verify actual factors, source conventions or data permissions.

`:strict` requires identical dates. `:intersection` returns results on common dates and reports unmatched dates on both sides. No common dates is an error; references are never fabricated. Each result contains the full maximum CDF difference, Wasserstein distance, mean/quantile cost errors and profit errors. Signed errors are estimate minus reference. Historical comparison evaluates profit ratios at that day's close by default; plain distribution comparison continues to default to reference-bin midpoints.

## Output behaviour

Inputs, simulation, metrics and reference comparisons are validated before results are created. Existing files, directories, hard links and symbolic links are rejected as output targets. Each result is first written to a temporary file in the same directory, then published with a hard link that cannot overwrite the target. Ordinary write failures clean up temporary files. The target filesystem must support hard links. Multiple outputs are published individually, not as a cross-file transaction; successfully published files remain if a later output fails.

See [Reference files](reference.md), [Adjustment events](adjustments.md) and [Market-data import](data.md) for formats. Real comparisons still need legitimate external samples with consistent definitions and recorded provenance.
