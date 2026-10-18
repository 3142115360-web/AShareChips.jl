using Test, TOML, Dates
include(joinpath(@__DIR__, "..", "examples", "compare_metrics_csv.jl"))

function _metric_cli_setup(folder)
    input = joinpath(folder, "daily.csv")
    reference = joinpath(folder, "reference.csv")
    output = joinpath(folder, "report.csv")
    path = joinpath(folder, "config.toml")
    write(input, "date,low,high,close,turnover,symbol\n" *
        "2000-01-03,8,10,9,0,TEST.SYNTHETIC\n" *
        "2000-01-04,10,12,11,50,TEST.SYNTHETIC\n" *
        "2000-01-05,10,12,11,0,TEST.SYNTHETIC\n")
    write(reference, "date,symbol,mean,cost_q50,price,ratio\n" *
        "2000-01-03,TEST.SYNTHETIC,9.25,9,9,25\n" *
        "2000-01-05,TEST.SYNTHETIC,10,10,10,50\n")
    config = Dict{String,Any}(
        "input" => input, "output" => output, "price_basis" => "unadjusted",
        "turnover_basis" => "float_shares", "turnover_unit" => "percent",
        "grid" => Dict("lower" => 8.0, "upper" => 12.0, "step" => 1.0),
        "model" => Dict("kind" => "uniform"),
        "reference" => Dict{String,Any}(
            "input" => reference, "price_basis" => "unadjusted", "profit_unit" => "percent",
            "matching" => "intersection", "quantiles" => [0.5], "quantile_columns" => ["cost_q50"],
            "columns" => Dict("date" => "date", "symbol" => "symbol", "mean_cost" => "mean",
                              "profit_price" => "price", "profit_ratio" => "ratio")))
    return (; input, reference, output, path, config)
end

_metric_cli_config(case) = open(io -> TOML.print(io, case.config), case.path, "w")

@testset "Scalar reference file workflow: analytical history and signed errors" begin
    mktempdir() do folder
        case = _metric_cli_setup(folder)
        _metric_cli_config(case)
        result = compare_metrics_csv(case.path)
        @test result.output == case.output
        @test length(result.rows) == 6
        @test result.estimate_only_dates == [Date(2000, 1, 4)]
        @test isempty(result.reference_only_dates)
        @test getproperty.(result.rows, :metric) ==
            ["mean_cost", "cost_quantile", "profit_ratio", "mean_cost", "cost_quantile", "profit_ratio"]
        @test result.rows[1].estimate == 9
        @test result.rows[1].reference == 9.25
        @test result.rows[1].error == -0.25
        @test result.rows[2].estimate == 9
        @test result.rows[2].quantile == 0.5
        @test result.rows[3].price == 9
        @test result.rows[3].estimate == 0.5
        @test result.rows[3].reference == 0.25
        @test result.rows[3].error == 0.25
        # Day 2 lacks a reference but still changes the day 3 distribution.
        @test result.rows[4].estimate == 10
        @test result.rows[5].estimate == 10
        @test result.rows[6].estimate == 0.5
        @test all(row -> row.error == 0, result.rows[4:6])
        @test readlines(case.output)[1] == "date,symbol,metric,quantile,price,estimate,reference,error"
        @test split(readlines(case.output)[2], ',')[4:5] == ["", ""]
        @test_throws ArgumentError compare_metrics_csv(case.path)
        @test length(readlines(case.output)) == 7
    end
end

@testset "Scalar reference matching checks both date sets" begin
    mktempdir() do folder
        case = _metric_cli_setup(folder)
        open(case.reference, "a") do io
            println(io, "2000-01-06,TEST.SYNTHETIC,11,11,11,50")
        end
        case.config["reference"]["matching"] = "strict"
        _metric_cli_config(case)
        @test_throws ArgumentError compare_metrics_csv(case.path)
        @test !ispath(case.output)
        case.config["reference"]["matching"] = "intersection"
        _metric_cli_config(case)
        result = compare_metrics_csv(case.path)
        @test result.estimate_only_dates == [Date(2000, 1, 4)]
        @test result.reference_only_dates == [Date(2000, 1, 6)]
        @test length(result.rows) == 6
    end
    mktempdir() do folder
        case = _metric_cli_setup(folder)
        write(case.reference, "date,symbol,mean,cost_q50,price,ratio\n2000-01-06,TEST.SYNTHETIC,11,11,11,50\n")
        _metric_cli_config(case)
        @test_throws ArgumentError compare_metrics_csv(case.path)
        @test !ispath(case.output)
    end
end

@testset "Strict matching keeps configured quantile order and date format" begin
    mktempdir() do folder
        case = _metric_cli_setup(folder)
        case.config["reference"]["matching"] = "strict"
        case.config["reference"]["profit_unit"] = "fraction"
        case.config["reference"]["dateformat"] = "yyyymmdd"
        case.config["reference"]["quantiles"] = [0.95, 0.05]
        case.config["reference"]["quantile_columns"] = ["upper", "lower"]
        case.config["reference"]["columns"] = Dict("date" => "day", "symbol" => "code")
        write(case.reference, "day,code,upper,lower\n" *
            "20000103,TEST.SYNTHETIC,9.9,8.1\n" *
            "20000104,TEST.SYNTHETIC,11.8,8.2\n" *
            "20000105,TEST.SYNTHETIC,11.8,8.2\n")
        _metric_cli_config(case)
        result = compare_metrics_csv(case.path)
        @test isempty(result.estimate_only_dates)
        @test isempty(result.reference_only_dates)
        @test getproperty.(result.rows, :quantile) == [0.95, 0.05, 0.95, 0.05, 0.95, 0.05]
        @test getproperty.(result.rows, :estimate) ≈ [9.9, 8.1, 11.8, 8.2, 11.8, 8.2]
        @test all(row -> isapprox(row.error, 0; atol=1e-14), result.rows)
    end
end

@testset "Scalar rows need explicit definitions, symbols and paired values" begin
    mktempdir() do folder
        case = _metric_cli_setup(folder)
        case.config["reference"]["columns"] = Dict("date" => "Day", "symbol" => "Code")
        case.config["reference"]["quantiles"] = [0.5]
        case.config["reference"]["quantile_columns"] = ["avgCost"]
        write(case.reference, "\ufeffDay,Code,avgCost\r\n2000-01-03,TEST.SYNTHETIC,9\r\n")
        _metric_cli_config(case)
        result = compare_metrics_csv(case.path)
        @test length(result.rows) == 1
        @test only(result.rows).metric == "cost_quantile"
        @test only(result.rows).quantile == 0.5
        @test only(result.rows).error == 0
    end
    mktempdir() do folder
        case = _metric_cli_setup(folder)
        case.config["symbol"] = "TEST.SYNTHETIC"
        write(case.reference, "date,mean,cost_q50,price,ratio\n2000-01-03,9,9,9,50\n")
        _metric_cli_config(case)
        @test length(compare_metrics_csv(case.path).rows) == 3
    end
    mktempdir() do folder
        case = _metric_cli_setup(folder)
        # A configured metric can be missing on an individual day; never fill it.
        write(case.reference, "date,symbol,mean,cost_q50,price,ratio\n" *
            "2000-01-03,TEST.SYNTHETIC,,9,,\n2000-01-05,TEST.SYNTHETIC,10,,,\n")
        _metric_cli_config(case)
        result = compare_metrics_csv(case.path)
        @test getproperty.(result.rows, :metric) == ["cost_quantile", "mean_cost"]
        @test all(row -> row.error == 0, result.rows)
    end
    invalid_rows = [
        "2000-01-03,,9,9,9,50\n", # empty known symbol
        "2000-01-03,OTHER.SYNTHETIC,9,9,9,50\n", # wrong security
        "2000-01-03,TEST.SYNTHETIC,,,,\n", # empty metrics
        "2000-01-03,TEST.SYNTHETIC,9,9,9,\n", # unpaired price
        "2000-01-03,TEST.SYNTHETIC,9,9,,50\n", # unpaired ratio
        "2000-01-03,TEST.SYNTHETIC,9,9,9,101\n", # bad percent unit
        "2000-01-03,TEST.SYNTHETIC,Inf,9,9,50\n",
        "2000-01-03,TEST.SYNTHETIC,-1,9,9,50\n",
        "2000-01-03,TEST.SYNTHETIC,1e-400,9,9,50\n",
        "2000-01-03,TEST.SYNTHETIC,9,9,9,5e-324\n", # percent conversion underflow
        "2000-1-3,TEST.SYNTHETIC,9,9,9,50\n",
        "2000-01-03,TEST.SYNTHETIC,9,9,9,50\n2000-01-03,TEST.SYNTHETIC,9,9,9,50\n",
        "2000-01-05,TEST.SYNTHETIC,9,9,9,50\n2000-01-03,TEST.SYNTHETIC,9,9,9,50\n",
        "2000-01-03,TEST.SYNTHETIC,9,9,9\n",
    ]
    for body in invalid_rows
        mktempdir() do folder
            case = _metric_cli_setup(folder)
            write(case.reference, "date,symbol,mean,cost_q50,price,ratio\n" * body)
            _metric_cli_config(case)
            @test_throws ArgumentError compare_metrics_csv(case.path)
            @test !ispath(case.output)
        end
    end
end

@testset "All scalar input and configuration validation precedes publication" begin
    for mutation in (
        config -> (config["reference"]["price_basis"] = "fixed_adjusted"),
        config -> (config["reference"]["profit_unit"] = "weights"),
        config -> (config["reference"]["profit_unit"] = "fraction"), # fixture has percent > 1
        config -> (config["reference"]["matching"] = "guess"),
        config -> (config["reference"]["quantile_columns"] = String[]),
        config -> (config["reference"]["quantiles"] = [1.1]),
        config -> (config["reference"]["quantiles"] = [0.5, 0.5];
                   config["reference"]["quantile_columns"] = ["cost_q50", "another_q50"]),
        config -> (config["reference"]["columns"]["mean_cost"] = "cost_q50"),
        config -> (config["reference"]["columns"]["profit_price"] = "missing"),
        config -> delete!(config["reference"]["columns"], "profit_ratio"),
        config -> (config["reference"]["columns"]["unknown"] = "unused"),
        config -> (config["grid"]["step"] = 0.0),
        config -> (config["model"]["kind"] = "guess"),
        config -> (config["model"]["turnover_model"] = "guess"),
        config -> (config["output"] = config["reference"]["input"]),
        config -> (config["output"] = config["input"]),
    )
        mktempdir() do folder
            case = _metric_cli_setup(folder)
            mutation(case.config)
            _metric_cli_config(case)
            @test_throws ArgumentError compare_metrics_csv(case.path)
            @test !ispath(case.output)
            @test startswith(read(case.input, String), "date,low,high")
            @test startswith(read(case.reference, String), "date,symbol,mean")
        end
    end
    mktempdir() do folder
        case = _metric_cli_setup(folder)
        case.config["reference"]["columns"] = Dict("date" => "date", "symbol" => "symbol")
        delete!(case.config["reference"], "quantiles")
        delete!(case.config["reference"], "quantile_columns")
        _metric_cli_config(case)
        @test_throws ArgumentError compare_metrics_csv(case.path)
        @test !ispath(case.output)
    end
    mktempdir() do folder
        case = _metric_cli_setup(folder)
        case.config["reference"]["quantiles"] = [0.1, 0.9]
        case.config["reference"]["quantile_columns"] = ["cost_q10", "cost_q90"]
        # Invalid quantile ordering on an extra reference day still rejects.
        write(case.reference, "date,symbol,mean,cost_q10,cost_q90,price,ratio\n" *
            "2000-01-03,TEST.SYNTHETIC,9,8.2,9.8,9,50\n" *
            "2000-01-06,TEST.SYNTHETIC,9,11,10,9,50\n")
        _metric_cli_config(case)
        @test_throws ArgumentError compare_metrics_csv(case.path)
        @test !ispath(case.output)
    end
    for csv in (
        "date,date,mean,cost_q50,price,ratio\n2000-01-03,TEST.SYNTHETIC,9,9,9,50\n",
        "date,symbol,mean,cost_q50,price,ratio,unused\n2000-01-03,TEST.SYNTHETIC,9,9,9,50,\"quoted\"\n",
        "date,mean,cost_q50,price,ratio\n2000-01-03,9,9,9,50\n", # no explicit reference symbol
    )
        mktempdir() do folder
            case = _metric_cli_setup(folder)
            write(case.reference, csv)
            _metric_cli_config(case)
            @test_throws ArgumentError compare_metrics_csv(case.path)
            @test !ispath(case.output)
        end
    end
    mktempdir() do folder
        case = _metric_cli_setup(folder)
        write(case.reference, UInt8[0xff, 0xfe])
        _metric_cli_config(case)
        @test_throws ArgumentError compare_metrics_csv(case.path)
        @test !ispath(case.output)
    end
    mktempdir() do folder
        case = _metric_cli_setup(folder)
        write(case.input, "date,low,high,close,turnover\n2000-01-03,8,10,9,0\n")
        _metric_cli_config(case)
        @test_throws ArgumentError compare_metrics_csv(case.path)
        @test !ispath(case.output)
    end
end

@testset "Scalar workflow corporate actions and output protection" begin
    mktempdir() do folder
        case = _metric_cli_setup(folder)
        write(case.input, "date,low,high,close,turnover,symbol\n" *
            "2000-01-03,8,10,9,0,TEST.SYNTHETIC\n2000-01-04,4,5,4.5,0,TEST.SYNTHETIC\n")
        write(case.reference, "date,symbol,mean,cost_q50,price,ratio\n2000-01-04,TEST.SYNTHETIC,4.5,4.5,4.5,50\n")
        events = joinpath(folder, "events.csv")
        write(events, "date,scale,shift,symbol\n2000-01-04,0.5,0,TEST.SYNTHETIC\n")
        case.config["events"] = events
        case.config["grid"] = Dict("lower" => 4.0, "upper" => 10.0, "step" => 1.0)
        _metric_cli_config(case)
        result = compare_metrics_csv(case.path)
        @test all(row -> row.error == 0, result.rows)
        case.config["output"] = joinpath(folder, "double-adjusted.csv")
        case.config["price_basis"] = "fixed_adjusted"
        case.config["reference"]["price_basis"] = "fixed_adjusted"
        _metric_cli_config(case)
        @test_throws ArgumentError compare_metrics_csv(case.path)
        @test !ispath(case.config["output"])
        case.config["output"] = events
        _metric_cli_config(case)
        @test_throws ArgumentError compare_metrics_csv(case.path)
        @test length(readlines(events)) == 2
    end
    for kind in (:file, :directory, :dangling_link)
        kind == :dangling_link && Sys.iswindows() && continue
        mktempdir() do folder
            case = _metric_cli_setup(folder)
            kind == :file && write(case.output, "preserve this\n")
            kind == :directory && mkdir(case.output)
            kind == :dangling_link && symlink(joinpath(folder, "absent.csv"), case.output)
            _metric_cli_config(case)
            @test_throws ArgumentError compare_metrics_csv(case.path)
            @test kind == :file ? read(case.output, String) == "preserve this\n" :
                  kind == :directory ? isdir(case.output) : islink(case.output)
        end
    end
end
