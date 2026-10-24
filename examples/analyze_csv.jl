using AShareCostDistributions
using TOML

function _config_key(config, name)
    haskey(config,name) || throw(ArgumentError("missing configuration key: $name"))
    return config[name]
end

function _report_cell(value)
    text = string(value)
    occursin(r"[,\"\r\n]",text) || return text
    return "\"" * replace(text,"\""=>"\"\"") * "\""
end

function _atomic_output(writer, output::AbstractString)
    (ispath(output) || islink(output)) && throw(ArgumentError("output already exists; choose a new output path"))
    mkpath(dirname(output))
    temporary, io = mktemp(dirname(output);cleanup=false)
    try
        writer(io)
        close(io)
        # A hard link publishes the complete file and fails if any destination
        # entry appeared meanwhile, including a dangling link. Never overwrite.
        hardlink(temporary,output)
    finally
        try
            isopen(io) && close(io)
        finally
            ispath(temporary) && rm(temporary;force=true)
        end
    end
    return output
end

function _available_output(input, output)
    input == output && throw(ArgumentError("output must differ from the input file"))
    (ispath(output) || islink(output)) && throw(ArgumentError("output already exists; choose a new output path"))
end

function analyze_csv(config_path::AbstractString)
    config = TOML.parsefile(config_path)
    folder = dirname(abspath(config_path))
    input = normpath(joinpath(folder,_config_key(config,"input")))
    output = normpath(joinpath(folder,_config_key(config,"output")))
    _available_output(input,output)
    series = read_bars(input;
        price_basis=Symbol(_config_key(config,"price_basis")),
        turnover_basis=Symbol(_config_key(config,"turnover_basis")),
        turnover_unit=Symbol(_config_key(config,"turnover_unit")),symbol=get(config,"symbol",nothing))
    settings = _config_key(config,"grid")
    lower, upper, step = (Float64(_config_key(settings,key)) for key in ("lower","upper","step"))
    all(isfinite,(lower,upper,step)) && 0 <= lower < upper && step > 0 ||
        throw(ArgumentError("grid must have finite 0 ≤ lower < upper and step > 0"))
    count = (upper-lower)/step
    isfinite(count) && count <= 1_000_000 || throw(ArgumentError("grid requests too many bins"))
    edges = collect(lower:step:upper)
    last(edges) < upper && push!(edges,upper)
    grid = PriceGrid(edges)
    model_config = get(config,"model",Dict{String,Any}())
    report_config = get(config,"report",Dict{String,Any}())
    kind = get(model_config,"kind","triangular")
    model = kind == "triangular" ? TriangularModel(peak=Symbol(get(model_config,"peak","typical"))) :
            kind == "uniform" ? UniformModel() : throw(ArgumentError("model.kind must be uniform or triangular"))
    law = get(model_config,"turnover_model","linear")
    k = get(model_config,"turnover_k",1.0)
    turnover = law == "linear" ? LinearTurnover(;k) :
               law == "exponential" ? ExponentialTurnover(;k) :
               throw(ArgumentError("turnover_model must be linear or exponential"))
    adjustments = haskey(config,"events") ? read_adjustments(normpath(joinpath(folder,config["events"])),series) : nothing
    coverage = get(report_config,"coverage",0.9)
    snapshots = dated_history(series; grid, model, turnover_model=turnover,adjustments)
    # Compute every row before creating the output, so invalid settings leave no partial file.
    rows = map(zip(snapshots,series.bars)) do (snapshot,bar)
        d = snapshot.distribution
        interval = concentration(d;coverage)
        (snapshot.date, something(series.symbol,""), bar.close, average_cost(d),
         profit_ratio(d,bar.close), cost_quantile(d,0.1), cost_quantile(d,0.5),
         cost_quantile(d,0.9), interval.lower, interval.upper, interval.relative_width)
    end
    comparison_result, comparison_output = nothing, nothing
    if haskey(config,"comparison")
        settings = config["comparison"]
        comparison_input = normpath(joinpath(folder,_config_key(settings,"input")))
        comparison_output = normpath(joinpath(folder,_config_key(settings,"output")))
        comparison_output == output && throw(ArgumentError("comparison and daily outputs must differ"))
        _available_output(comparison_input,comparison_output)
        reference = read_distributions(comparison_input;
            price_basis=Symbol(_config_key(settings,"price_basis")),
            mass_unit=Symbol(_config_key(settings,"mass_unit")),symbol=get(settings,"symbol",nothing))
        comparison_result = compare_history(series,reference;grid,
            matching=Symbol(get(settings,"matching","strict")),
            require_symbol_match=get(settings,"require_symbol_match",true),
            model,turnover_model=turnover,adjustments)
    end
    _atomic_output(output) do io
        println(io,"date,symbol,close,average_cost,profit_fraction,cost_q10,cost_q50,cost_q90,interval_lower,interval_upper,relative_width")
        for row in rows
            println(io,join(_report_cell.(row),','))
        end
    end
    if !isnothing(comparison_result)
        _atomic_output(comparison_output) do io
            println(io,"date,symbol,close,max_cdf_error,wasserstein1,mean_cost_error,cost_q10_error,cost_q50_error,cost_q90_error,profit_at_close_error")
            for row in comparison_result.rows
                fields = (row.date,something(series.symbol,""),row.close,row.max_cdf_error,
                    row.wasserstein1,row.mean_cost_error,row.quantile_errors...,only(row.profit_errors))
                println(io,join(_report_cell.(fields),','))
            end
        end
        println("Compared ",length(comparison_result.rows)," reference dates to ",comparison_output)
        println("Observation dates without reference: ",comparison_result.estimate_only_dates)
        println("Reference dates without observations: ",comparison_result.reference_only_dates)
    end
    println("Saved ",length(rows)," observations to ",output)
    println("Price basis: ",series.price_basis,"; turnover denominator: ",series.turnover_basis)
    return output
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 1 || error("Usage: julia --project=. examples/analyze_csv.jl CONFIG.toml")
    analyze_csv(only(ARGS))
end
