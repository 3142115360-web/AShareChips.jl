# Dated cost adjustment events

Historical unadjusted bars can cross a corporate action. Their older cost
histogram then needs a declared coordinate transform before the event day's
turnover update:

```math
p_{\mathrm{new}} = s p_{\mathrm{old}} + b, \qquad s > 0.
```

`read_adjustments` imports a sparse table of these events and returns one
`PriceAdjustment` for every observation in a `BarSeries`. Dates not listed in
the table receive `PriceAdjustment()` (`scale=1`, `shift=0`). Events are aligned
by exact observation date, rather than row number.

```julia
using AShareCostDistributions

series = read_bars("daily.csv";
    price_basis=:unadjusted, turnover_basis=:float_shares,
    turnover_unit=:percent, symbol="000001.SYNTHETIC")
adjustments = read_adjustments("events.csv", series)
history = dated_history(series;
    grid=PriceGrid(collect(0.0:0.01:30.0)), adjustments)
```

The simple, unquoted event table uses this header:

```text
date,scale,shift,symbol
2000-01-04,0.5,0,000001.SYNTHETIC
```

This deliberately synthetic example expresses a halving of historical cost
coordinates. It is a parser and model demonstration, not an actual adjustment
factor for a real security. Both scale and shift must be supplied; missing cells
are errors. Finite negative shifts are permitted, but a later simulation rejects
transformed occupied costs outside the nonnegative price domain or its grid.

## Exact dates and security identity

Events must be strictly increasing, without duplicates, and every event date
must occur in `series.dates`. An event on a missing trading day, suspended day,
or a date outside the chosen window produces an error with the physical file
line. No event is silently discarded, moved to the next observation, or composed
with another row. Select the analysis window and event dates deliberately; when
an action precedes the first observation, provide the resulting coordinate basis
or a suitable prior explicitly.

The optional `symbol` column, when present, must be nonempty on every event.
`series.symbol` must also be known and must match all event symbols exactly,
including leading zeroes and suffixes. This prevents attaching a labelled event
file to an anonymous or different security. If the symbol column is absent or
explicitly disabled in `columns`, ownership is the caller's assertion. A file
containing only a valid header means no events and works for an anonymous series
too. Empty files without a header are rejected.

```julia
using Dates

# A provider's alternative headers, tab delimiter and compact date format.
adjustments = read_adjustments("provider-events.tsv", series;
    columns=(date=:trade_date, scale=:factor, shift=:offset, symbol=:code),
    dateformat=dateformat"yyyymmdd", delimiter='\t')
```

Fixed-adjusted bars are already in one common coordinate system and accept only
identity events. Applying nonidentity events to them would adjust costs twice.
On an unadjusted series, an event on its first observation is accepted by the
reader. Simulation then requires `initial` to represent a histogram immediately
before the first event; without that prior the engine rejects the event because
there is no earlier histogram to transform. The first day's observed prices are
already in the post-event coordinates.

## Factor provenance and model limits

The reader never infers an action from a close-price jump. Supply factors from a
verified data provider or a stated model and retain the source, effective date,
units and corporate action interpretation in the research record. Cumulative
adjustment factors are not automatically converted into per-event scale and
shift. Verify their direction and coordinate definition before importing them.

An affine price-coordinate change alone does not model new shares, rights
subscription, share cancellation, tax treatment, changes in tradable float, or
the allocation of holdings across investor accounts. Turnover fractions must
still use the declared denominator consistently. A dividend may motivate a cost
shift under one accounting convention but a different adjustment under another;
the package does not choose between them. Document these assumptions alongside
any comparison with market software.

Grid edges must cover both historical and current occupied costs. The engine
conserves probability under a valid transformation and rejects clipping instead
of silently normalizing away out-of-grid holdings. Repeated rebasing onto a
fixed histogram can introduce discretization error, so compare grid resolutions
when using multiple events.

## File and IO contract

This import follows `read_bars`: first nonblank physical line is the header;
blank lines are ignored; a UTF-8 BOM on the first physical line and CRLF endings
are accepted; headers and cells are trimmed. Header names must be nonempty and
unique. Dates must exactly match the declared format, row widths must be
consistent, and numbers must be finite. Quotes and malformed UTF-8 are rejected
even in extra columns. Use a general CSV parser upstream for quoted, multiline
or escaped data, then construct aligned `PriceAdjustment` values explicitly.

An IO argument is consumed and kept open even on a validation error. The path
method owns and closes its stream. Error messages contain physical line numbers
so that blank lines do not obscure which source row failed.

```@docs
read_adjustments
```
