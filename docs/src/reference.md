# Importing reference cost distributions

`ReferenceSeries` stores dates, reference distributions and a price basis for one security. It accepts prepared reference histograms from sources such as published research algorithms or data exports that the caller has permission to use. Successful import establishes format and probability consistency, not reproduction of Tongdaxin or another provider's algorithm.

The repository's `examples/fixtures/reference_synthetic.csv` is entirely hand-constructed synthetic data, not output from Tongdaxin, a broker or a market data provider:

```text
date,bin_left,bin_right,mass,symbol
2000-01-03,8,10,0.75,000001.SYNTHETIC
2000-01-03,10,12,0.25,000001.SYNTHETIC
2000-01-04,8,10,0.5,000001.SYNTHETIC
2000-01-04,10,12,0.5,000001.SYNTHETIC
```

```julia
using AShareCostDistributions, Dates

reference = read_distributions("examples/fixtures/reference_synthetic.csv";
                               price_basis=:unadjusted)
@assert trade_dates(reference) == [Date(2000, 1, 3), Date(2000, 1, 4)]
@assert probabilities(reference.distributions[1]) == [0.75, 0.25]
@assert average_cost(reference.distributions[1]) == 9.5
```

Each row represents a price interval. `mass` is its probability mass, not density, bar height, cumulative profit ratio or trading volume. Each interval uses the same uniform density interpretation as `ChipDistribution`. Convert point costs, cumulative probabilities or bar heights upstream according to the provider's published definition; the package does not infer their meaning.

## Explicit mass units

| Parameter | Meaning | Daily validation |
|---|---|---|
| `mass_unit=:fraction`, the default | `0.75` represents 75% of holdings | Total mass must be within `mass_tolerance` of 1 |
| `mass_unit=:percent` | `75` represents 75% of holdings | Each value is divided by 100, then the same total check applies |
| `mass_unit=:weights` | Explicitly declares nonnegative relative weights | Each day needs positive total weight, then it is normalized |

`mass_tolerance` defaults to `1e-6`. It is the absolute difference of the total from 1 and must be finite and nonnegative. After the total passes, construction normalizes accepted rounding error. In the default mode, percentage data summing to 100, twice-divided percentages summing to 0.01, missing mass and excessive probability totals are rejected; units are never corrected automatically. `:weights` explicitly permits arbitrary-weight normalization. Finite weights whose unscaled total overflows are normalized after scaling.

All edges and masses must be representable as finite `Float64` values and be nonnegative. Zero-mass bins are allowed, but a day's mass cannot be entirely zero. Each right edge must exceed its left edge, with finite width. Bins within a day must be ascending and contiguous: one bin's right edge must equal the next bin's left edge numerically and exactly. Overlaps, gaps and repeated bins are rejected. Resolve inconsistent boundaries explicitly upstream; the adapter does not merge approximate matches.

Positive mass that becomes unrepresentable zero during text conversion, division by 100 or normalization raises an explicit error. It is not treated as an intentional zero-mass bin. For excessively disparate weight scales, choose a representable numerical model or an explicit approximation upstream.

## Dates, security and price basis

All bins for a date must be adjacent, and date groups must increase strictly. An earlier date cannot reappear later. Different dates may use different grids. Dates must match the declared `DateFormat` completely; the default rejects truncated or differently formatted dates such as `2000-01` and `2000-1-3`. The adapter does not sort, fill trading days, infer suspensions or correct information-availability times.

`price_basis` is required and follows `BarSeries`:

- `:unadjusted` means that each snapshot uses that date's contemporaneous unadjusted price coordinates.
- `:fixed_adjusted` means that every snapshot shares one fixed adjusted coordinate system.

Constructors and readers record these declarations without inferring or applying corporate-action adjustments. For daily model comparisons, the researcher must verify the security, basis, corporate-action mappings, initial state, coverage, dates and availability times. Two `:fixed_adjusted` labels do not ensure the same adjustment basis. A basis incorporating future actions can introduce look-ahead information.

The `symbol` column is optional. If present, each row must contain a nonempty, consistent string; leading zeroes and suffixes are preserved. A separate `symbol="000001.SYNTHETIC"` argument is allowed, and file identifiers must match it. A single file cannot contain multiple securities.

A reference series can also be constructed directly:

```julia
reference = ReferenceSeries(
    [Date(2000, 1, 3), Date(2000, 1, 4)],
    [ChipDistribution(PriceGrid([8, 10, 12]), [3, 1]),
     ChipDistribution(PriceGrid([7, 9, 11, 13]), [0, 1, 1])];
    price_basis=:unadjusted, symbol="000001.SYNTHETIC")
```

These `ChipDistribution` values are already normalized. Dates and distributions must have equal, nonzero lengths, and dates must increase strictly. Construction copies the dates, distribution vector, and each snapshot's edge and mass arrays, so subsequent changes to the original inputs do not alter the snapshots. Treat internal fields as read-only; use `trade_dates`, `bin_edges` and `probabilities` to obtain copies.

## Simple unquoted tables and custom columns

`read_distributions` follows the same simple table rules as `read_bars`: the first nonblank physical line is the header; blank lines are ignored; a UTF-8 BOM at the start of the first physical line and CRLF endings are accepted; headers and cells are trimmed; errors include physical line numbers. Empty or duplicate headers, inconsistent row widths, invalid UTF-8 and double quotes in any column are rejected. This is not a general CSV parser; use a complete parser such as CSV.jl upstream for quoting, escapes, embedded delimiters or multiline fields.

```julia
io = IOBuffer("day;L;R;W;Code\n03/01/2000;8;10;75;000001.SYNTHETIC\n" *
              "03/01/2000;10;12;25;000001.SYNTHETIC\n")
reference = read_distributions(io; price_basis=:unadjusted, mass_unit=:percent,
    delimiter=';', dateformat=dateformat"dd/mm/yyyy",
    columns=(date=:day, left=:L, right=:R, mass=:W, symbol=:Code))
@assert isopen(io)
```

The `columns` NamedTuple must map `date/left/right/mass`; `symbol` may be omitted or set to `nothing`. Mapped names must be distinct, nonempty Strings or Symbols, matching the case-sensitive headers. Extra columns are ignored but still subject to quoting and row-width validation. The delimiter must be a single character other than a double quote or newline.

For a path, the adapter opens and closes the file. For an IO argument, it leaves the caller's stream open on success and failure. Record real reference data permissions, provider algorithm definitions and discrepancies separately. These synthetic examples validate parsing and hand-calculated probabilities only; they provide no evidence of real-market or Tongdaxin compatibility.
