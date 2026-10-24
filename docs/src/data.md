# Dated series and data import

`BarSeries` stores observation dates, daily bars and research assumptions for one security. The price basis and turnover denominator must be supplied explicitly. These labels record the caller's declarations; the package cannot verify a provider's actual conventions.

```julia
using AShareCostDistributions, Dates

bars = [DailyBar(low=9, high=11, close=10, turnover=0.05),
        DailyBar(low=9.5, high=12, close=11, turnover=0.12)]
series = BarSeries([Date(2000, 1, 3), Date(2000, 1, 5)], bars;
                  price_basis=:unadjusted, turnover_basis=:float_shares,
                  symbol="000001.SYNTHETIC")
grid = PriceGrid(collect(8.0:0.02:14.0))
history = dated_history(series; grid)
chips = chip_distribution(series; grid)
@assert history[2].date == Date(2000, 1, 5)
@assert probabilities(chips) ≈ probabilities(history[end].distribution)
```

All dates, prices and security identifiers above are synthetic.

## Price and turnover conventions

| Parameter | Value | Declared meaning |
|---|---|---|
| `price_basis` | `:unadjusted` | Contemporaneous unadjusted prices; earlier costs can be explicitly mapped on event days |
| `price_basis` | `:fixed_adjusted` | All historical prices already share one fixed adjusted coordinate basis |
| `turnover_basis` | `:float_shares` | Tradable float is the turnover denominator |
| `turnover_basis` | `:free_float_shares` | Free float is the turnover denominator |
| `turnover_basis` | `:total_shares` | Total shares are the turnover denominator |
| `turnover_basis` | `:provider_reported` | Provider-reported turnover whose denominator has not been independently verified; does not assert any of the three definitions above |

`DailyBar.turnover` always stores a fraction: `0.05` means 5%, and values greater than 1 are allowed. Changing denominator metadata does not recalculate turnover. Prepare consistent inputs upstream using the security, date and provider's definitions.

A `:fixed_adjusted` series rejects nonidentity `PriceAdjustment` values to prevent double adjustment. Both the default `adjustments=nothing` and per-day identity adjustments are accepted. `initial` must already share the series' price coordinates; a probability distribution alone cannot establish this. A fixed basis involving future corporate actions requires a separate look-ahead assessment in backtests.

Dates must be nonempty, match the bars in length and increase strictly. Duplicates and unordered dates are rejected. No automatic sorting, deduplication, calendar filling, suspension inference or information-availability inference is performed. `trade_dates` returns a copy. Construction copies the date and bar inputs; internal fields are treated as read-only.

`chip_distribution(series)` returns the final `ChipDistribution`; `chip_history(series)` returns a vector of states. `dated_history(series)` returns `(date=..., distribution=...)` entries, each representing the state after that observation's update. Model, prior and grid parameters follow the same API as plain bar inputs.

## Simple unquoted delimited files

`read_bars` is a minimal table adapter using the `Dates` standard library, with no external data service or parser dependency. It is not a general CSV parser: every double quote is rejected, including in extra columns. For quoted fields, embedded delimiters, escapes, multiline fields or complex missing-value types, use a full parser such as CSV.jl upstream, then construct `DailyBar` and `BarSeries` inputs.

The repository's `examples/fixtures/daily_synthetic.csv` has this format. All rows are synthetic.

```text
date,low,high,close,turnover,vwap,symbol
2000-01-03,9,11,10,5,10,000001.SYNTHETIC
2000-01-04,9.5,12,11,12,,000001.SYNTHETIC
2000-01-05,10,12.5,12,8,11.5,000001.SYNTHETIC
```

```julia
series = read_bars("examples/fixtures/daily_synthetic.csv";
                   price_basis=:unadjusted, turnover_basis=:float_shares,
                   turnover_unit=:percent)
@assert series.bars[1].turnover == 0.05
@assert series.bars[2].vwap === nothing
```

The default `turnover_unit=:fraction` interprets `0.05` as 5%. With `:percent`, input `5` means 5% and is divided by 100. The adapter does not guess units, calculate VWAP, derive turnover from volume and share counts, or obtain adjustment factors.

- The first nonblank physical line is the header. Blank lines anywhere are ignored; error line numbers retain the original physical numbering.
- UTF-8 BOM is accepted only at the start of the first physical line. CRLF is accepted. Leading and trailing whitespace is trimmed from headers and values.
- Header names are case-sensitive; duplicate or empty names are rejected. Each nonblank data row must have the same number of columns as the header.
- `date/low/high/close/turnover` are required and cannot be blank. Numbers must convert to finite `Float64` values and pass `DailyBar` range checks. Dates must match the declared `DateFormat` exactly and completely: the default `yyyy-mm-dd` rejects `2000-01` and `2000-1-3`.
- `vwap` and `symbol` columns may be absent. A blank VWAP cell becomes `nothing`. When present, the symbol column must contain a nonempty, consistent identifier on every row. Leading zeroes and suffixes, such as `000001` and `600000.SH`, are retained; the exchange is not inferred.
- A separate `symbol="..."` argument is allowed; identifiers in the file must match it. A file cannot mix securities.
- Extra columns are ignored but must satisfy the unquoted format and row-width rules. At least one observation is required.
- For a path, the adapter opens and closes the stream. For an IO object, it consumes the input but leaves the caller's stream open on both success and failure.

## Custom headers, dates and delimiters

```julia
io = IOBuffer("day;L;H;C;T;Code\n03/01/2000;9;11;10;5;000001.SYNTHETIC\n")
series = read_bars(io; price_basis=:unadjusted, turnover_basis=:float_shares,
    turnover_unit=:percent, delimiter=';', dateformat=dateformat"dd/mm/yyyy",
    columns=(date=:day, low=:L, high=:H, close=:C, turnover=:T, symbol=:Code))
@assert isopen(io)
```

The `columns` NamedTuple maps model fields to input headers. Required fields must be mapped; `vwap/symbol` may be omitted or mapped to `nothing`. Mapped names must be distinct and may be strings or Symbols. `delimiter` must be a single character other than a double quote or newline.

See [Data and corporate-action assumptions](assumptions.md) for cleaning, licensing and factor responsibilities. Comparisons with real market data or Tongdaxin require legitimately obtained, auditable inputs with explicit conventions.
