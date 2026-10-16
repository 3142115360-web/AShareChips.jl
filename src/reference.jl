"""
    ReferenceSeries(dates::AbstractVector{Date},
                    distributions::AbstractVector{ChipDistribution};
                    price_basis, symbol=nothing)

Dated reference cost histograms for one security. Dates and distributions must
have equal, nonzero lengths; dates must be strictly increasing. Each snapshot
may use a different price grid. Dates, the snapshot vector and each snapshot's
grid/mass arrays are copied. Treat the stored fields as read-only; use
[`trade_dates`](@ref), [`bin_edges`](@ref) and [`probabilities`](@ref) for copies.

`price_basis` is the caller's required declaration: `:unadjusted` means each
snapshot uses that date's historical price coordinates; `:fixed_adjusted` means
all snapshots use one fixed adjusted coordinate system. This label and optional
`symbol` use the same meanings as [`BarSeries`](@ref). They do not establish
data provenance, availability time, corporate-action treatment or agreement
with a provider's unpublished algorithm. No adjustment or calendar filling is
performed. Input `ChipDistribution` values are already normalized histograms.
"""
struct ReferenceSeries
    dates::Vector{Date}
    distributions::Vector{ChipDistribution}
    price_basis::Symbol
    symbol::Union{Nothing,String}
    function ReferenceSeries(dates::AbstractVector{Date},
                             distributions::AbstractVector{ChipDistribution};
                             price_basis, symbol=nothing)
        price_basis isa Symbol && price_basis in _PRICE_BASES ||
            throw(ArgumentError("price_basis must be :unadjusted or :fixed_adjusted"))
        isempty(dates) && throw(ArgumentError("at least one dated distribution is required"))
        length(dates) == length(distributions) ||
            throw(ArgumentError("dates/distributions size mismatch"))
        owned_dates = collect(dates)
        all(i -> owned_dates[i] < owned_dates[i+1], 1:length(owned_dates)-1) ||
            throw(ArgumentError("dates must be strictly increasing, without duplicates"))
        new(owned_dates, [deepcopy(d) for d in distributions],
            price_basis, _series_symbol(symbol))
    end
end

"Return an independent copy of reference dates; no trading calendar is inferred."
trade_dates(series::ReferenceSeries) = copy(series.dates)

const _REFERENCE_COLUMNS = (date=:date, left=:bin_left, right=:bin_right,
                            mass=:mass, symbol=:symbol)
const _REQUIRED_REFERENCE_COLUMNS = (:date, :left, :right, :mass)

function _reference_column_names(columns)
    columns isa NamedTuple || throw(ArgumentError("columns must be a named tuple of header names"))
    all(name -> name in keys(_REFERENCE_COLUMNS), keys(columns)) ||
        throw(ArgumentError("columns contains an unsupported field"))
    all(name -> name in keys(columns), _REQUIRED_REFERENCE_COLUMNS) ||
        throw(ArgumentError("columns must map date, left, right and mass"))
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

function _reference_distribution(edges, mass, mass_unit, mass_tolerance, line)
    if mass_unit != :weights
        total = sum(mass)
        isfinite(total) || _line_error(line, "daily probability mass sum must be finite")
        total > 0 || _line_error(line, "daily probability mass sum must be positive")
        abs(total - 1.0) <= mass_tolerance ||
            _line_error(line, "daily probability mass must sum to 1 within mass_tolerance; check mass_unit")
    else
        any(>(0), mass) || _line_error(line, "daily weights must have positive total mass")
    end
    # Input bins and probability sums have been checked before normalization.
    # The scale-first constructor also permits finite weights whose raw sum overflows.
    return try
        ChipDistribution(PriceGrid(edges), mass)
    catch error
        error isa ArgumentError || rethrow()
        _line_error(line, sprint(showerror, error))
    end
end

"""
    read_distributions(path_or_io; price_basis, mass_unit=:fraction,
                       symbol=nothing, dateformat=dateformat"yyyy-mm-dd",
                       columns=(date=:date, left=:bin_left, right=:bin_right,
                                mass=:mass, symbol=:symbol),
                       delimiter=',', mass_tolerance=1e-6)

Read a **simple unquoted delimited file** of reference histograms into a
[`ReferenceSeries`](@ref). Each row contains one bin, described by its left and
right boundaries and its probability mass (not density). For each date, rows
must be consecutive with strictly positive, finite bin widths, finite
nonnegative boundaries and exactly adjoining boundaries in ascending order.
Zero-mass bins are permitted. Dates must exactly match the declared format;
date groups must be strictly increasing. Grids may differ across dates. No
sorting, merging of duplicate bins, gap filling or rebasing is performed.

`mass_unit=:fraction` requires each day's sum to be 1 within the nonnegative
finite absolute `mass_tolerance`; `:percent` divides each mass by 100 before the
same check. Only the explicit `:weights` setting normalizes arbitrary finite
nonnegative weights with a positive total. Fraction/percent inputs with an
incorrect total or overflowing sum are rejected instead of silently fixing
their units. Positive masses that underflow to zero during percent conversion
or normalization are rejected. Accepted rounding discrepancies are normalized
by the histogram constructor. Price basis is required and uses the
[`BarSeries`](@ref) contract.

The first nonblank physical line is the header; blank lines are ignored.
UTF-8 BOM on the first line and CRLF are accepted. Header names and values are
trimmed; errors report physical line numbers. Duplicate/empty headers, wrong
row widths, invalid UTF-8 and any double quote are rejected, including quotes
in unused columns. Use a complete parser such as CSV.jl upstream for quoted
CSV, then construct a series. `columns` maps date/left/right/mass to exact header
names; optional symbol may be absent, omitted from the mapping, or mapped to
`nothing`. A present symbol column must be nonempty and consistent on every
row, and must agree with a supplied `symbol`; leading zeroes are preserved.
Extra columns are ignored. A supplied IO is consumed but never closed; a path
method manages its own stream. This adapter neither acquires reference data
nor verifies its license or its equivalence to a particular market terminal.
"""
function read_distributions(io::IO; price_basis, mass_unit=:fraction,
                            symbol=nothing, dateformat::DateFormat=dateformat"yyyy-mm-dd",
                            columns=_REFERENCE_COLUMNS, delimiter=',', mass_tolerance=1e-6)
    price_basis isa Symbol && price_basis in _PRICE_BASES ||
        throw(ArgumentError("price_basis must be :unadjusted or :fixed_adjusted"))
    mass_unit isa Symbol && mass_unit in (:fraction, :percent, :weights) ||
        throw(ArgumentError("mass_unit must be :fraction, :percent or :weights"))
    mass_tolerance isa Real || throw(ArgumentError("mass_tolerance must be a nonnegative finite number"))
    tolerance = _finite(mass_tolerance, "mass_tolerance")
    tolerance >= 0 || throw(ArgumentError("mass_tolerance must be nonnegative"))
    delimiter isa Char && !(delimiter in ('"', '\n', '\r')) ||
        throw(ArgumentError("delimiter must be a character other than double quote or newline"))
    names = _reference_column_names(columns)
    series_symbol = _series_symbol(symbol)
    header = nothing
    indices = Dict{Symbol,Int}()
    dates, distributions = Date[], ChipDistribution[]
    group_date = nothing
    edges, mass = Float64[], Float64[]
    last_line, group_last_line = 0, 0
    for (line, input) in enumerate(eachline(io))
        last_line = line
        raw = line == 1 && startswith(input, '\ufeff') ? chop(input; head=1, tail=0) : input
        isvalid(raw) || _line_error(line, "input must be valid UTF-8")
        isempty(strip(raw)) && continue
        occursin('"', raw) && _line_error(line,
            "quoted fields are unsupported; parse with CSV.jl before constructing ReferenceSeries")
        fields = _delimited_fields(raw, delimiter, line)
        if isnothing(header)
            all(!isempty, fields) || _line_error(line, "header names must not be empty")
            length(unique(fields)) == length(fields) || _line_error(line, "duplicate header names")
            header = fields
            for field in keys(names)
                index = findfirst(==(names[field]), header)
                if isnothing(index)
                    field in _REQUIRED_REFERENCE_COLUMNS &&
                        _line_error(line, "missing required column $(names[field])")
                else
                    indices[field] = index
                end
            end
            continue
        end
        length(fields) == length(header) || _line_error(line, "row width does not match header")
        date = _bar_date(fields[indices[:date]], dateformat, line)
        if !isnothing(group_date) && date != group_date
            date > group_date || _line_error(line, "date groups must be strictly increasing, without duplicates")
            push!(dates, group_date)
            push!(distributions, _reference_distribution(edges, mass, mass_unit, tolerance, group_last_line))
            empty!(edges)
            empty!(mass)
        end
        group_date = date
        left = _bar_number(fields[indices[:left]], :bin_left, line)
        right = _bar_number(fields[indices[:right]], :bin_right, line)
        left >= 0 || _line_error(line, "bin boundaries must be nonnegative")
        right > left && isfinite(right - left) ||
            _line_error(line, "each bin must have positive finite width")
        if isempty(edges)
            push!(edges, left)
        else
            left == edges[end] || _line_error(line, "daily bin boundaries must adjoin exactly in ascending order")
        end
        weight = _bar_number(fields[indices[:mass]], :mass, line)
        weight >= 0 || _line_error(line, "mass must be nonnegative")
        if mass_unit == :percent
            converted_weight = weight / 100
            weight > 0 && converted_weight == 0 &&
                _line_error(line, "positive percent mass must not underflow to zero during conversion")
            weight = converted_weight
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
        push!(edges, right)
        push!(mass, weight)
        group_last_line = line
    end
    isnothing(header) && _line_error(max(last_line, 1), "a header and at least one distribution are required")
    isnothing(group_date) && _line_error(max(last_line, 1), "at least one distribution is required")
    push!(dates, group_date)
    push!(distributions, _reference_distribution(edges, mass, mass_unit, tolerance, group_last_line))
    return ReferenceSeries(dates, distributions; price_basis, symbol=series_symbol)
end

function read_distributions(path::AbstractString; kwargs...)
    return open(path, "r") do io
        read_distributions(io; kwargs...)
    end
end
