using AShareCostDistributions, Dates, TOML

# Share the existing report publication helper without running its command line.
if !isdefined(@__MODULE__, :_atomic_output)
    include(joinpath(@__DIR__, "analyze_csv.jl"))
end

_metric_line_error(line, message) = throw(ArgumentError("line $line: $message"))

function _metric_number(raw, name, line)
    value = tryparse(Float64, raw)
    (isnothing(value) || !isfinite(value)) &&
        _metric_line_error(line, "$name must be a finite number")
    if iszero(value)
        exact = tryparse(BigFloat, raw)
        (!isnothing(exact) && !iszero(exact)) &&
            _metric_line_error(line, "$name is nonzero but underflows Float64")
    end
    value >= 0 || _metric_line_error(line, "$name must be nonnegative")
    return value
end

function _metric_symbol(value)
    isnothing(value) && return nothing
    value isa AbstractString && !isempty(strip(value)) ||
        throw(ArgumentError("symbol must be a nonempty string"))
    return String(strip(value))
end

function _metric_columns(settings)
    columns = get(settings, "columns", Dict{String,Any}())
    columns isa AbstractDict || throw(ArgumentError("reference.columns must be a table"))
    allowed = ("date", "symbol", "mean_cost", "profit_price", "profit_ratio")
    all(key -> key in allowed, keys(columns)) ||
        throw(ArgumentError("unsupported reference column mapping"))
    names = Dict("date" => get(columns, "date", "date"),
                 "symbol" => get(columns, "symbol", "symbol"))
    for key in ("mean_cost", "profit_price", "profit_ratio")
        haskey(columns, key) && (names[key] = columns[key])
    end
    haskey(names, "profit_price") == haskey(names, "profit_ratio") ||
        throw(ArgumentError("map profit_price and profit_ratio together"))
    quantiles = get(settings, "quantiles", Any[])
    quantile_columns = get(settings, "quantile_columns", Any[])
    quantiles isa AbstractVector && quantile_columns isa AbstractVector ||
        throw(ArgumentError("quantiles and quantile_columns must be arrays"))
    length(quantiles) == length(quantile_columns) ||
        throw(ArgumentError("quantiles and quantile_columns must have equal lengths"))
    qvalues = Float64[]
    for q in quantiles
        q isa Real || throw(ArgumentError("quantiles must be numeric"))
        x = Float64(q)
        isfinite(x) && 0 <= x <= 1 || throw(ArgumentError("quantiles must be in [0,1]"))
        q > 0 && x == 0 && throw(ArgumentError("positive quantile underflows Float64"))
        push!(qvalues, x)
    end
    length(unique(qvalues)) == length(qvalues) ||
        throw(ArgumentError("configured quantiles must be distinct"))
    all_names = vcat(collect(values(names)), collect(quantile_columns))
    all(name -> name isa AbstractString && !isempty(strip(name)), all_names) ||
        throw(ArgumentError("column names must be nonempty strings"))
    clean_names = String.(strip.(all_names))
    length(unique(clean_names)) == length(clean_names) ||
        throw(ArgumentError("column mappings must have distinct names"))
    names = Dict(key => String(strip(value)) for (key, value) in names)
    qcolumns = String.(strip.(quantile_columns))
    (haskey(names, "mean_cost") || haskey(names, "profit_ratio") || !isempty(qvalues)) ||
        throw(ArgumentError("configure at least one reference metric"))
    return names, qvalues, qcolumns
end

function _read_metric_reference(path, settings; symbol=nothing)
    basis = Symbol(_config_key(settings, "price_basis"))
    basis in (:unadjusted, :fixed_adjusted) ||
        throw(ArgumentError("reference.price_basis must be unadjusted or fixed_adjusted"))
    unit = Symbol(_config_key(settings, "profit_unit"))
    unit in (:fraction, :percent) ||
        throw(ArgumentError("reference.profit_unit must be fraction or percent"))
    names, qvalues, qcolumns = _metric_columns(settings)
    known_symbol = _metric_symbol(get(settings, "symbol", symbol))
    dateformat = DateFormat(get(settings, "dateformat", "yyyy-mm-dd"))
    rows = NamedTuple[]
    open(path, "r") do io
        header, indices = nothing, Dict{String,Int}()
        last_line = 0
        for (line, input) in enumerate(eachline(io))
            last_line = line
            raw = line == 1 && startswith(input, '\ufeff') ? chop(input; head=1, tail=0) : input
            isvalid(raw) || _metric_line_error(line, "input must be valid UTF-8")
            isempty(strip(raw)) && continue
            occursin('"', raw) && _metric_line_error(line, "quoted CSV fields are unsupported")
            fields = String.(strip.(split(raw, ','; keepempty=true)))
            if isnothing(header)
                all(!isempty, fields) || _metric_line_error(line, "header names must not be empty")
                length(unique(fields)) == length(fields) || _metric_line_error(line, "duplicate header names")
                header = fields
                for name in vcat(collect(values(names)), qcolumns)
                    index = findfirst(==(name), header)
                    if isnothing(index)
                        name == names["symbol"] && !isnothing(known_symbol) && continue
                        _metric_line_error(line, "missing configured column $name")
                    end
                    indices[name] = index
                end
                continue
            end
            length(fields) == length(header) || _metric_line_error(line, "row width does not match header")
            rawdate = fields[indices[names["date"]]]
            date = tryparse(Date, rawdate, dateformat)
            (isnothing(date) || Dates.format(date, dateformat) != rawdate) &&
                _metric_line_error(line, "date must exactly match the declared dateformat")
            !isempty(rows) && date <= rows[end].date &&
                _metric_line_error(line, "dates must be strictly increasing, without duplicates")
            if haskey(indices, names["symbol"])
                current = fields[indices[names["symbol"]]]
                isempty(current) && _metric_line_error(line, "symbol must not be empty")
                if isnothing(known_symbol)
                    known_symbol = current
                elseif current != known_symbol
                    _metric_line_error(line, "mixed symbols or conflict with specified symbol")
                end
            end
            mean = nothing
            if haskey(names, "mean_cost")
                text = fields[indices[names["mean_cost"]]]
                isempty(text) || (mean = _metric_number(text, "mean_cost", line))
            end
            qs, costs = Float64[], Float64[]
            for (q, name) in zip(qvalues, qcolumns)
                text = fields[indices[name]]
                isempty(text) && continue
                push!(qs, q)
                push!(costs, _metric_number(text, "quantile cost", line))
            end
            # Check even unmatched rows; validation never drops bad references.
            for i in eachindex(qs), j in eachindex(qs)
                qs[i] < qs[j] && costs[i] > costs[j] &&
                    _metric_line_error(line, "reference costs must be nondecreasing in quantile")
            end
            prices, ratios = Float64[], Float64[]
            if haskey(names, "profit_ratio")
                price_text = fields[indices[names["profit_price"]]]
                ratio_text = fields[indices[names["profit_ratio"]]]
                isempty(price_text) == isempty(ratio_text) ||
                    _metric_line_error(line, "profit price and ratio must both be present or both be empty")
                if !isempty(price_text)
                    price = _metric_number(price_text, "profit price", line)
                    ratio = _metric_number(ratio_text, "profit ratio", line)
                    ratio <= (unit == :percent ? 100 : 1) ||
                        _metric_line_error(line, "profit ratio outside declared unit range; check profit_unit")
                    unit == :percent && ratio > 0 && ratio / 100 == 0 &&
                        _metric_line_error(line, "positive percent ratio underflows during conversion")
                    push!(prices, price)
                    push!(ratios, ratio)
                end
            end
            (!isnothing(mean) || !isempty(qs) || !isempty(prices)) ||
                _metric_line_error(line, "each reference row must supply at least one metric")
            push!(rows, (; date, mean_cost=mean, quantiles=qs, quantile_costs=costs,
                         prices, profit_ratios=ratios))
        end
        isempty(rows) && _metric_line_error(max(last_line, 1), "a header and at least one metric row are required")
    end
    isnothing(known_symbol) && throw(ArgumentError("reference security symbol must be known"))
    return (; rows, symbol=known_symbol, price_basis=basis, profit_unit=unit)
end

"""
    compare_metrics_csv(config_path)

Compare a complete simulated daily history with explicitly mapped scalar
references. Errors are estimate minus reference; profit values in the report
are fractions. No histogram or distribution distance is inferred from scalars.
Validate all input rows before publishing a new, non-overwriting report.
"""
function compare_metrics_csv(config_path::AbstractString)
    config = TOML.parsefile(config_path)
    folder = dirname(abspath(config_path))
    input = normpath(joinpath(folder, _config_key(config, "input")))
    output = normpath(joinpath(folder, _config_key(config, "output")))
    settings = _config_key(config, "reference")
    reference_input = normpath(joinpath(folder, _config_key(settings, "input")))
    for protected in (input, reference_input, abspath(config_path))
        _available_output(protected, output)
    end
    if haskey(config, "events")
        _available_output(normpath(joinpath(folder, config["events"])), output)
    end
    series = read_bars(input;
        price_basis=Symbol(_config_key(config, "price_basis")),
        turnover_basis=Symbol(_config_key(config, "turnover_basis")),
        turnover_unit=Symbol(_config_key(config, "turnover_unit")),
        symbol=get(config, "symbol", nothing))
    isnothing(series.symbol) && throw(ArgumentError("observation security symbol must be known"))
    reference = _read_metric_reference(reference_input, settings; symbol=get(config, "symbol", nothing))
    reference.symbol == series.symbol || throw(ArgumentError("observation and reference symbols must agree"))
    reference.price_basis == series.price_basis || throw(ArgumentError("observation and reference price bases must agree"))
    matching = Symbol(get(settings, "matching", "strict"))
    matching in (:strict, :intersection) || throw(ArgumentError("matching must be strict or intersection"))
    observation_dates = trade_dates(series)
    reference_dates = [row.date for row in reference.rows]
    estimate_only_dates = setdiff(observation_dates, reference_dates)
    reference_only_dates = setdiff(reference_dates, observation_dates)
    matching == :strict && (!isempty(estimate_only_dates) || !isempty(reference_only_dates)) &&
        throw(ArgumentError("strict matching requires identical observation and reference dates"))
    isempty(intersect(observation_dates, reference_dates)) && throw(ArgumentError("no common dates to compare"))
    grid_config = _config_key(config, "grid")
    lower, upper, step = (Float64(_config_key(grid_config, key)) for key in ("lower", "upper", "step"))
    all(isfinite, (lower, upper, step)) && 0 <= lower < upper && step > 0 ||
        throw(ArgumentError("grid must have finite 0 ≤ lower < upper and step > 0"))
    count = (upper - lower) / step
    isfinite(count) && count <= 1_000_000 || throw(ArgumentError("grid requests too many bins"))
    edges = collect(lower:step:upper)
    last(edges) < upper && push!(edges, upper)
    grid = PriceGrid(edges)
    model_config = get(config, "model", Dict{String,Any}())
    kind = get(model_config, "kind", "triangular")
    model = kind == "triangular" ? TriangularModel(peak=Symbol(get(model_config, "peak", "typical"))) :
            kind == "uniform" ? UniformModel() : throw(ArgumentError("model.kind must be uniform or triangular"))
    law = get(model_config, "turnover_model", "linear")
    k = get(model_config, "turnover_k", 1.0)
    turnover = law == "linear" ? LinearTurnover(; k) :
               law == "exponential" ? ExponentialTurnover(; k) :
               throw(ArgumentError("turnover_model must be linear or exponential"))
    adjustments = haskey(config, "events") ?
        read_adjustments(normpath(joinpath(folder, config["events"])), series) : nothing
    # Preserve every observation in the recursion, including days without references.
    snapshots = dated_history(series; grid, model, turnover_model=turnover, adjustments)
    estimates = Dict(snapshot.date => snapshot.distribution for snapshot in snapshots)
    rows = NamedTuple[]
    for row in reference.rows
        haskey(estimates, row.date) || continue
        comparison = compare_metrics(estimates[row.date]; mean_cost=row.mean_cost,
            quantiles=row.quantiles, quantile_costs=row.quantile_costs,
            prices=row.prices, profit_ratios=row.profit_ratios, profit_unit=reference.profit_unit)
        if !isnothing(comparison.mean_cost_reference)
            push!(rows, (date=row.date, symbol=series.symbol, metric="mean_cost", quantile=nothing,
                price=nothing, estimate=comparison.mean_cost_estimate,
                reference=comparison.mean_cost_reference, error=comparison.mean_cost_error))
        end
        for i in eachindex(comparison.quantiles)
            push!(rows, (date=row.date, symbol=series.symbol, metric="cost_quantile",
                quantile=comparison.quantiles[i], price=nothing,
                estimate=comparison.quantile_estimates[i], reference=comparison.quantile_references[i],
                error=comparison.quantile_errors[i]))
        end
        for i in eachindex(comparison.prices)
            push!(rows, (date=row.date, symbol=series.symbol, metric="profit_ratio", quantile=nothing,
                price=comparison.prices[i], estimate=comparison.profit_estimates[i],
                reference=comparison.profit_references[i], error=comparison.profit_errors[i]))
        end
    end
    _atomic_output(output) do io
        println(io, "date,symbol,metric,quantile,price,estimate,reference,error")
        for row in rows
            println(io, join([isnothing(value) ? "" : _report_cell(value) for value in values(row)], ','))
        end
    end
    println("Compared ", length(rows), " scalar metrics to ", output)
    println("Observation dates without reference: ", estimate_only_dates)
    println("Reference dates without observations: ", reference_only_dates)
    return (; output, rows, estimate_only_dates, reference_only_dates)
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 1 || error("Usage: julia --project=. examples/compare_metrics_csv.jl CONFIG.toml")
    compare_metrics_csv(only(ARGS))
end
