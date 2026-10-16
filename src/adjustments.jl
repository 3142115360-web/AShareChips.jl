const _ADJUSTMENT_COLUMNS = (date=:date, scale=:scale, shift=:shift, symbol=:symbol)
const _REQUIRED_ADJUSTMENT_COLUMNS = (:date, :scale, :shift)

function _adjustment_column_names(columns)
    columns isa NamedTuple || throw(ArgumentError("columns must be a named tuple of header names"))
    all(name -> name in keys(_ADJUSTMENT_COLUMNS), keys(columns)) ||
        throw(ArgumentError("columns contains an unsupported adjustment field"))
    all(name -> name in keys(columns), _REQUIRED_ADJUSTMENT_COLUMNS) ||
        throw(ArgumentError("columns must map date, scale and shift"))
    names = Dict{Symbol,String}()
    for field in keys(columns)
        name = getproperty(columns, field)
        isnothing(name) && field == :symbol && continue
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

"""
    read_adjustments(path_or_io, series::BarSeries;
                     columns=(date=:date, scale=:scale, shift=:shift, symbol=:symbol),
                     dateformat=dateformat"yyyy-mm-dd", delimiter=',')

Read a **simple unquoted delimited event file**, aligning explicit
[`PriceAdjustment`](@ref)s with `series` observations. Return a
`Vector{PriceAdjustment}` of length `length(series.bars)`. Dates omitted from the
event file receive identity adjustments. Every event date must exactly match an
observation date; duplicate, unsorted, missing-calendar and out-of-range dates
are errors. A header-only file returns all identities; an input without a header
is rejected.

Date, scale and shift columns are required. Scale must be finite and positive;
shift must be finite, and both cells are required even for identities. A present
symbol column requires a nonempty value on every event, and `series.symbol` must
be known and match it exactly. If the column is absent, omitted from `columns`
or mapped to `nothing`, the caller asserts the events belong to `series`.
Fixed-adjusted series accept only identity events to avoid double adjustment.

The map `p_new = scale * p_old + shift` applies to the previous cost histogram
before that date's turnover update. Supply factors explicitly from a verified
provider or a declared model; this reader does not infer events from price jumps
or interpret share issuance and float changes. A nonidentity event on the first
observation can be read, but simulation requires an explicit `initial`
distribution in the coordinate system immediately before that event.

The file rules match [`read_bars`](@ref): first nonblank physical line is the
header, blank lines are ignored, leading UTF-8 BOM on the first physical line
and CRLF are accepted, headers/cells are trimmed, and errors report physical
line numbers. Quotes, invalid UTF-8, duplicate/empty headers and inconsistent
row widths are rejected, including in unused columns. Extra columns are ignored.
Use CSV.jl upstream for general CSV. A supplied IO is consumed but never closed;
the path method opens and closes its own stream.
"""
function read_adjustments(io::IO, series::BarSeries; columns=_ADJUSTMENT_COLUMNS,
                          dateformat::DateFormat=dateformat"yyyy-mm-dd", delimiter=',')
    delimiter isa Char && !(delimiter in ('"', '\n', '\r')) ||
        throw(ArgumentError("delimiter must be a character other than double quote or newline"))
    names = _adjustment_column_names(columns)
    changes = fill(PriceAdjustment(), length(series.bars))
    header = nothing
    indices = Dict{Symbol,Int}()
    previous_date = nothing
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
                    field in _REQUIRED_ADJUSTMENT_COLUMNS &&
                        _line_error(line, "missing required column $(names[field])")
                else
                    indices[field] = index
                end
            end
            continue
        end
        length(fields) == length(header) || _line_error(line, "row width does not match header")
        date = _bar_date(fields[indices[:date]], dateformat, line)
        !isnothing(previous_date) && date <= previous_date &&
            _line_error(line, "event dates must be strictly increasing, without duplicates")
        index = searchsortedfirst(series.dates, date)
        (index <= length(series.dates) && series.dates[index] == date) ||
            _line_error(line, "event date $date has no matching observation in series")
        scale = _bar_number(fields[indices[:scale]], :scale, line)
        scale > 0 || _line_error(line, "scale must be positive")
        shift = _bar_number(fields[indices[:shift]], :shift, line)
        if haskey(indices, :symbol)
            value = fields[indices[:symbol]]
            isempty(value) && _line_error(line, "symbol must not be empty when its column is present")
            isnothing(series.symbol) &&
                _line_error(line, "series.symbol must be specified when event symbols are present")
            value == series.symbol ||
                _line_error(line, "event symbol does not match series.symbol")
        end
        change = PriceAdjustment(; scale, shift)
        series.price_basis == :fixed_adjusted && !_identity(change) &&
            _line_error(line, "fixed-adjusted prices must use identity adjustments to avoid double adjustment")
        changes[index] = change
        previous_date = date
    end
    isnothing(header) && _line_error(max(last_line, 1), "an adjustment header is required")
    return changes
end

function read_adjustments(path::AbstractString, series::BarSeries; kwargs...)
    return open(path, "r") do io
        read_adjustments(io, series; kwargs...)
    end
end
