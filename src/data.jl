const _PRICE_BASES = (:unadjusted, :fixed_adjusted)
const _TURNOVER_BASES = (:float_shares, :free_float_shares, :total_shares)

function _validate_bases(price_basis, turnover_basis)
    price_basis isa Symbol && price_basis in _PRICE_BASES ||
        throw(ArgumentError("price_basis must be :unadjusted or :fixed_adjusted"))
    turnover_basis isa Symbol && turnover_basis in _TURNOVER_BASES ||
        throw(ArgumentError("turnover_basis must be :float_shares, :free_float_shares or :total_shares"))
    return nothing
end

function _series_symbol(symbol)
    isnothing(symbol) && return nothing
    symbol isa AbstractString || throw(ArgumentError("symbol must be a nonempty string or nothing"))
    value = String(strip(symbol))
    isempty(value) && throw(ArgumentError("symbol must be a nonempty string or nothing"))
    return value
end

"""
    BarSeries(dates::AbstractVector{Date}, bars::AbstractVector{DailyBar};
              price_basis, turnover_basis, symbol=nothing)

Owned daily observations for one security, with explicit data provenance choices.
Dates and bars are copied, must have equal nonzero lengths, and dates must be
strictly increasing. No sorting, calendar filling, exchange inference or units
conversion is performed. `symbol` is an optional nonempty string; leading zeroes
and suffixes are preserved. Treat the stored vectors as read-only.

`price_basis` is `:unadjusted` (historical prices on each observation date) or
`:fixed_adjusted` (all prices already expressed in one fixed coordinate system).
`turnover_basis` identifies the denominator of the supplied fractions:
`:float_shares`, `:free_float_shares` or `:total_shares`. These labels record the
caller's assertion; the package cannot verify a provider's adjustment factors,
calendar or denominator. Fixed-adjusted series reject nonidentity adjustments.
"""
struct BarSeries
    dates::Vector{Date}
    bars::Vector{DailyBar}
    symbol::Union{Nothing,String}
    price_basis::Symbol
    turnover_basis::Symbol
    function BarSeries(dates::AbstractVector{Date}, bars::AbstractVector{DailyBar};
                       price_basis, turnover_basis, symbol=nothing)
        _validate_bases(price_basis, turnover_basis)
        isempty(dates) && throw(ArgumentError("at least one dated observation is required"))
        length(dates) == length(bars) || throw(ArgumentError("dates/bars size mismatch"))
        owned_dates, owned_bars = collect(dates), collect(bars)
        all(i -> owned_dates[i] < owned_dates[i+1], 1:length(owned_dates)-1) ||
            throw(ArgumentError("dates must be strictly increasing, without duplicates"))
        new(owned_dates, owned_bars, _series_symbol(symbol), price_basis, turnover_basis)
    end
end

"Return an independent copy of the observation dates; no trading calendar is inferred."
trade_dates(series::BarSeries) = copy(series.dates)

function _series_adjustments(series::BarSeries, adjustments)
    isnothing(adjustments) && return nothing
    # Materialize once, so validating a generator does not consume it before simulation.
    changes = collect(adjustments)
    (length(changes) == length(series.bars) && all(a -> a isa PriceAdjustment, changes)) ||
        throw(ArgumentError("provide one PriceAdjustment per observation"))
    if series.price_basis == :fixed_adjusted && any(a -> !_identity(a), changes)
        throw(ArgumentError("fixed-adjusted prices must use identity adjustments to avoid double adjustment"))
    end
    return changes
end

"""
    chip_distribution(series::BarSeries; grid, adjustments=nothing, kwargs...)

Final histogram for a dated series. Return type and model keywords match the
bar-vector method. Fixed-adjusted series allow only identity adjustments; an
explicit `initial` distribution must already use the series' price basis.
"""
function chip_distribution(series::BarSeries; adjustments=nothing, kwargs...)
    return chip_distribution(series.bars;
                             adjustments=_series_adjustments(series, adjustments), kwargs...)
end

"""
    chip_history(series::BarSeries; grid, adjustments=nothing, kwargs...)

Return the vector of distributions after each dated observation, preserving the
bar-vector return type and model keywords. Use [`dated_history`](@ref) when dates
must travel with each snapshot. Fixed-adjusted series reject nonidentity changes.
"""
function chip_history(series::BarSeries; adjustments=nothing, kwargs...)
    return chip_history(series.bars;
                        adjustments=_series_adjustments(series, adjustments), kwargs...)
end

"""
    dated_history(series::BarSeries; grid, kwargs...)

Return a vector of `(date=Date(...), distribution=ChipDistribution(...))` named
tuples, in input order. Each date denotes the state after that observation;
missing dates are not filled. Keywords match [`chip_history`](@ref).
"""
function dated_history(series::BarSeries; kwargs...)
    history = chip_history(series; kwargs...)
    return [(date=date, distribution=distribution)
            for (date, distribution) in zip(series.dates, history)]
end

const _BAR_COLUMNS = (date=:date, low=:low, high=:high, close=:close,
                      turnover=:turnover, vwap=:vwap, symbol=:symbol)
const _REQUIRED_BAR_COLUMNS = (:date, :low, :high, :close, :turnover)
_line_error(line::Integer, message) = throw(ArgumentError("line $line: $message"))

function _column_names(columns)
    columns isa NamedTuple || throw(ArgumentError("columns must be a named tuple of header names"))
    all(name -> name in keys(_BAR_COLUMNS), keys(columns)) ||
        throw(ArgumentError("columns contains an unsupported field"))
    all(name -> name in keys(columns), _REQUIRED_BAR_COLUMNS) ||
        throw(ArgumentError("columns must map date, low, high, close and turnover"))
    names = Dict{Symbol,String}()
    for field in keys(columns)
        name = getproperty(columns, field)
        if isnothing(name) && !(field in _REQUIRED_BAR_COLUMNS)
            continue
        end
        name isa Union{Symbol,AbstractString} ||
            throw(ArgumentError("column names must be symbols or nonempty strings"))
        value = String(strip(string(name)))
        isempty(value) && throw(ArgumentError("column names must be nonempty"))
        names[field] = value
    end
    length(unique(collect(values(names)))) == length(names) ||
        throw(ArgumentError("column mappings must use distinct header names"))
    return names
end

function _delimited_fields(raw, delimiter, line)
    isvalid(raw) || _line_error(line, "input must be valid UTF-8")
    occursin('"', raw) && _line_error(line, "quoted fields are unsupported; parse with CSV.jl before constructing BarSeries")
    return [String(strip(value)) for value in split(raw, delimiter; keepempty=true)]
end

function _bar_number(raw, field, line)
    isempty(raw) && _line_error(line, "$field must not be empty")
    value = tryparse(Float64, raw)
    (isnothing(value) || !isfinite(value)) && _line_error(line, "$field must be a finite number")
    if iszero(value)
        exact = tryparse(BigFloat, raw)
        (!isnothing(exact) && !iszero(exact)) &&
            _line_error(line, "$field is nonzero but underflows Float64")
    end
    return value
end

function _bar_date(raw, format, line)
    isempty(raw) && _line_error(line, "date must not be empty")
    date = tryparse(Date, raw, format)
    # Dates permits truncated components; require the complete declared representation.
    (isnothing(date) || Dates.format(date, format) != raw) &&
        _line_error(line, "date must exactly match the declared dateformat")
    return date
end

"""
    read_bars(path_or_io; price_basis, turnover_basis, turnover_unit=:fraction,
              dateformat=dateformat"yyyy-mm-dd", columns=(date=:date, low=:low,
              high=:high, close=:close, turnover=:turnover, vwap=:vwap,
              symbol=:symbol), delimiter=',', symbol=nothing)

Read a **simple unquoted delimited file** into a [`BarSeries`](@ref). This is not
a general CSV parser: any double quote is rejected, including in unused columns.
For quoted, multiline or escaped CSV, use CSV.jl upstream and then construct a
series. The first nonblank physical line is the header; blank lines are ignored,
and errors report physical line numbers. UTF-8 BOM on the first line and CRLF
are accepted. Header names and cell values are trimmed; duplicate/empty headers,
inconsistent row widths, invalid dates/numbers and mixed symbols are rejected.

Required columns are date/low/high/close/turnover. VWAP and symbol columns may
be absent; empty VWAP means `nothing`, while a present symbol column requires a
nonempty, consistent string on every row. Extra columns are ignored. `columns`
maps fields to exact header names (symbols or strings); optional fields may be
omitted or mapped to `nothing`. Dates must exactly match the supplied `DateFormat`
and be strictly increasing. No sorting, deduplication, VWAP calculation or
turnover inference is performed.

`turnover_unit=:fraction` means 0.05 is 5%; `:percent` divides the input by 100.
Prices and turnover denominators are caller-declared, required basis keywords.
The optional `symbol` must match any symbols found in the file. Leading zeroes
and exchange suffixes are retained. A supplied IO is consumed but never closed;
the path method opens and closes its own stream.
"""
function read_bars(io::IO; price_basis, turnover_basis, turnover_unit=:fraction,
                   dateformat::DateFormat=dateformat"yyyy-mm-dd", columns=_BAR_COLUMNS,
                   delimiter=',', symbol=nothing)
    _validate_bases(price_basis, turnover_basis)
    turnover_unit isa Symbol && turnover_unit in (:fraction, :percent) ||
        throw(ArgumentError("turnover_unit must be :fraction or :percent"))
    delimiter isa Char && !(delimiter in ('"', '\n', '\r')) ||
        throw(ArgumentError("delimiter must be a character other than double quote or newline"))
    names = _column_names(columns)
    series_symbol = _series_symbol(symbol)
    header = nothing
    indices = Dict{Symbol,Int}()
    dates, bars = Date[], DailyBar[]
    last_line = 0
    for (line, input) in enumerate(eachline(io))
        last_line = line
        raw = line == 1 && startswith(input, '\ufeff') ? chop(input; head=1, tail=0) : input
        isvalid(raw) || _line_error(line, "input must be valid UTF-8")
        isempty(strip(raw)) && continue
        fields = _delimited_fields(raw, delimiter, line)
        if isnothing(header)
            all(!isempty, fields) || _line_error(line, "header names must not be empty")
            length(unique(fields)) == length(fields) || _line_error(line, "duplicate header names")
            header = fields
            for field in keys(names)
                index = findfirst(==(names[field]), header)
                if isnothing(index)
                    field in _REQUIRED_BAR_COLUMNS && _line_error(line, "missing required column $(names[field])")
                else
                    indices[field] = index
                end
            end
            continue
        end
        length(fields) == length(header) || _line_error(line, "row width does not match header")
        date = _bar_date(fields[indices[:date]], dateformat, line)
        !isempty(dates) && date <= dates[end] &&
            _line_error(line, "dates must be strictly increasing, without duplicates")
        low = _bar_number(fields[indices[:low]], :low, line)
        high = _bar_number(fields[indices[:high]], :high, line)
        close = _bar_number(fields[indices[:close]], :close, line)
        turnover = _bar_number(fields[indices[:turnover]], :turnover, line)
        turnover >= 0 || _line_error(line, "turnover must be nonnegative")
        if turnover_unit == :percent
            before = turnover
            turnover /= 100
            before > 0 && turnover == 0 && _line_error(line, "turnover underflows when converting percent to fraction")
        end
        vwap = if haskey(indices, :vwap) && !isempty(fields[indices[:vwap]])
            _bar_number(fields[indices[:vwap]], :vwap, line)
        else
            nothing
        end
        if haskey(indices, :symbol)
            value = fields[indices[:symbol]]
            isempty(value) && _line_error(line, "symbol must not be empty when its column is present")
            if isnothing(series_symbol)
                series_symbol = value
            elseif value != series_symbol
                _line_error(line, "mixed symbols or conflict with specified symbol")
            end
        end
        bar = try
            DailyBar(; low, high, close, turnover, vwap)
        catch error
            error isa ArgumentError || rethrow()
            _line_error(line, sprint(showerror, error))
        end
        push!(dates, date)
        push!(bars, bar)
    end
    isnothing(header) && _line_error(max(last_line, 1), "a header and at least one observation are required")
    isempty(dates) && _line_error(max(last_line, 1), "at least one observation is required")
    return BarSeries(dates, bars; price_basis, turnover_basis, symbol=series_symbol)
end

function read_bars(path::AbstractString; kwargs...)
    return open(path, "r") do io
        read_bars(io; kwargs...)
    end
end
