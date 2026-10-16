using Dates

@testset "Dated series and explicit data import" begin
    @testset "Validated, owned series metadata" begin
        dates = [Date(2000, 1, 3), Date(2000, 1, 5)]
        bars = [DailyBar(low=8, high=10, close=9, turnover=0.05),
                DailyBar(low=10, high=12, close=11, turnover=0.1)]
        series = BarSeries(dates, bars; price_basis=:unadjusted,
                           turnover_basis=:float_shares, symbol=" 000001.SZ ")
        @test series.symbol == "000001.SZ"
        @test series.price_basis == :unadjusted
        @test series.turnover_basis == :float_shares
        @test series.bars == bars
        @test trade_dates(series) == dates
        dates[1] = Date(1999, 1, 1)
        bars[1] = bars[2]
        returned = trade_dates(series)
        returned[1] = Date(1998, 1, 1)
        @test series.dates[1] == Date(2000, 1, 3)
        @test series.bars[1].close == 9
        @test trade_dates(series)[1] == Date(2000, 1, 3)
        @test series.bars !== bars
        @test series.dates !== dates

        one_bar = [DailyBar(low=8, high=10, close=9, turnover=0.05)]
        for price_basis in (:unadjusted, :fixed_adjusted),
            turnover_basis in (:float_shares, :free_float_shares, :total_shares)
            one = BarSeries([Date(2000, 1, 3)], one_bar; price_basis, turnover_basis)
            @test one.symbol === nothing
            @test one.price_basis == price_basis
            @test one.turnover_basis == turnover_basis
        end
        @test_throws UndefKeywordError BarSeries([Date(2000, 1, 3)], one_bar;
                                               turnover_basis=:float_shares)
        @test_throws UndefKeywordError BarSeries([Date(2000, 1, 3)], one_bar;
                                               price_basis=:unadjusted)
        for invalid in (:unknown, "unadjusted", nothing, missing)
            @test_throws ArgumentError BarSeries([Date(2000, 1, 3)], one_bar;
                                                price_basis=invalid, turnover_basis=:float_shares)
        end
        for invalid in (:unknown, "float_shares", nothing, missing)
            @test_throws ArgumentError BarSeries([Date(2000, 1, 3)], one_bar;
                                                price_basis=:unadjusted, turnover_basis=invalid)
        end
        for invalid in ("", "   ", :stock, 1)
            @test_throws ArgumentError BarSeries([Date(2000, 1, 3)], one_bar;
                price_basis=:unadjusted, turnover_basis=:float_shares, symbol=invalid)
        end
        @test_throws ArgumentError BarSeries(Date[], DailyBar[];
            price_basis=:unadjusted, turnover_basis=:float_shares)
        @test_throws ArgumentError BarSeries([Date(2000, 1, 3), Date(2000, 1, 4)], one_bar;
            price_basis=:unadjusted, turnover_basis=:float_shares)
        for invalid in ([Date(2000, 1, 3), Date(2000, 1, 3)],
                        [Date(2000, 1, 4), Date(2000, 1, 3)])
            @test_throws ArgumentError BarSeries(invalid, repeat(one_bar, 2);
                price_basis=:unadjusted, turnover_basis=:float_shares)
        end
    end

    @testset "History alignment and adjustment contract" begin
        dates = [Date(2000, 1, 3), Date(2000, 1, 5)]
        bars = [DailyBar(low=8, high=10, close=9, turnover=0.05),
                DailyBar(low=10, high=12, close=11, turnover=0.1)]
        grid = PriceGrid([4, 6, 8, 10, 12])
        series = BarSeries(dates, bars; price_basis=:unadjusted, turnover_basis=:float_shares)
        fixed = BarSeries(dates, bars; price_basis=:fixed_adjusted, turnover_basis=:float_shares)
        vector_history = chip_history(bars; grid, model=UniformModel())
        for input in (series, fixed)
            history = chip_history(input; grid, model=UniformModel())
            dated = dated_history(input; grid, model=UniformModel())
            @test history isa Vector{ChipDistribution}
            @test length(history) == length(dates)
            @test [snapshot.date for snapshot in dated] == dates
            @test all(keys(snapshot) == (:date, :distribution) for snapshot in dated)
            @test all(probabilities(history[i]) ≈ probabilities(vector_history[i]) for i in eachindex(history))
            @test all(probabilities(dated[i].distribution) ≈ probabilities(history[i]) for i in eachindex(history))
            @test probabilities(chip_distribution(input; grid, model=UniformModel())) ≈
                  probabilities(history[end])
            identities = (PriceAdjustment() for _ in dates)
            @test probabilities(chip_distribution(input; grid, model=UniformModel(), adjustments=identities)) ≈
                  probabilities(history[end])
        end
        changes = [PriceAdjustment(), PriceAdjustment(scale=0.5)]
        @test probabilities(chip_distribution(series; grid, adjustments=changes, model=UniformModel())) ≈
              probabilities(chip_distribution(bars; grid, adjustments=changes, model=UniformModel()))
        for function_under_test in (chip_distribution, chip_history, dated_history)
            @test_throws ArgumentError function_under_test(fixed; grid, adjustments=changes)
            @test_throws ArgumentError function_under_test(fixed; grid,
                adjustments=(change for change in changes))
            @test_throws ArgumentError function_under_test(series; grid, adjustments=[PriceAdjustment()])
            @test_throws ArgumentError function_under_test(series; grid, adjustments=[1, 2])
        end
        prior = ChipDistribution(grid, [0, 0, 1, 0])
        @test probabilities(chip_distribution(fixed; grid, initial=prior, model=UniformModel())) ≈
              probabilities(chip_distribution(bars; grid, initial=prior, model=UniformModel()))
    end

    @testset "Simple delimited input, units and provenance" begin
        fixture = joinpath(@__DIR__, "..", "examples", "fixtures", "daily_synthetic.csv")
        series = read_bars(fixture; price_basis=:unadjusted, turnover_basis=:float_shares,
                           turnover_unit=:percent)
        @test series.symbol == "000001.SYNTHETIC"
        @test trade_dates(series) == [Date(2000, 1, 3), Date(2000, 1, 4), Date(2000, 1, 5)]
        @test [bar.turnover for bar in series.bars] ≈ [0.05, 0.12, 0.08]
        @test [bar.vwap for bar in series.bars] == [10, nothing, 11.5]
        header = "date,low,high,close,turnover\n"
        row = "2000-01-03,8,10,9,0.05\n"
        minimal = read_bars(IOBuffer(header * row); price_basis=:fixed_adjusted,
                            turnover_basis=:total_shares, symbol="600000.SH")
        @test minimal.symbol == "600000.SH"
        @test minimal.bars[1].vwap === nothing
        @test minimal.bars[1].turnover == 0.05
        @test minimal.price_basis == :fixed_adjusted
        @test minimal.turnover_basis == :total_shares
        io = IOBuffer("\ufeff\r\n  \r\n date , low , high , close , turnover , symbol , unused \r\n" *
                      "2000-01-03,8,10,9,5,000001,ignored\r\n\r\n" *
                      "2000-01-05,8,10,9,10,000001,ignored\r\n")
        bom = read_bars(io; price_basis=:unadjusted, turnover_basis=:free_float_shares,
                        turnover_unit=:percent)
        @test isopen(io)
        @test eof(io)
        @test bom.symbol == "000001"
        @test [bar.turnover for bar in bom.bars] == [0.05, 0.1]
        @test trade_dates(bom) == [Date(2000, 1, 3), Date(2000, 1, 5)]
        @test read_bars(IOBuffer("\ufeff" * header * row);
            price_basis=:unadjusted, turnover_basis=:float_shares).bars[1].close == 9

        custom = read_bars(IOBuffer("day;L;H;C;T;Code;W;comment\n03/01/2000;8;10;9;5;600000.SH;9;example\n");
            price_basis=:unadjusted, turnover_basis=:float_shares, turnover_unit=:percent,
            delimiter=';', dateformat=dateformat"dd/mm/yyyy",
            columns=(date=:day, low=:L, high=:H, close=:C, turnover=:T, symbol=:Code, vwap=:W),
            symbol="600000.SH")
        @test trade_dates(custom) == [Date(2000, 1, 3)]
        @test custom.symbol == "600000.SH"
        @test custom.bars[1].vwap == 9
        @test custom.bars[1].turnover == 0.05
        for columns in ((date=:date, low=:low, high=:high, close=:close, turnover=:turnover),
                        (date="date", low="low", high="high", close="close", turnover="turnover",
                         vwap=nothing, symbol=nothing))
            result = read_bars(IOBuffer(header * row); price_basis=:unadjusted,
                               turnover_basis=:float_shares, columns)
            @test result.symbol === nothing
            @test result.bars[1].vwap === nothing
        end
        @test read_bars(IOBuffer(header * "2000-01-03,8,10,9,150\n");
            price_basis=:unadjusted, turnover_basis=:float_shares, turnover_unit=:percent).bars[1].turnover == 1.5
    end

    @testset "Invalid input is rejected with physical line context" begin
        header = "date,low,high,close,turnover\n"
        row = "2000-01-03,8,10,9,0.05\n"
        invalid_rows = (
            "2000-01-03,8,10,9,\n", "2000-01-03,8,10,9,NaN\n",
            "2000-01-03,8,10,9,Inf\n", "2000-01-03,,10,9,0.05\n",
            "2000-01-03,nope,10,9,0.05\n", "2000-01-03,8,10,11,0.05\n",
            "2000-01-03,8,10,9,-0.05\n", "2000-02-30,8,10,9,0.05\n",
            "2000-01,8,10,9,0.05\n", "2000-1-3,8,10,9,0.05\n",
            ",8,10,9,0.05\n", "2000-01-03,8,10,9,0.05,extra\n",
            "2000-01-03,8,10,9\n", "\"2000-01-03\",8,10,9,0.05\n",
        )
        for invalid in invalid_rows
            io = IOBuffer("\n" * header * "\n" * invalid)
            error = try
                read_bars(io; price_basis=:unadjusted, turnover_basis=:float_shares)
                nothing
            catch caught
                caught
            end
            @test error isa ArgumentError
            @test occursin("line 4:", sprint(showerror, error))
            @test isopen(io)
        end
        for invalid_header in ("date,low,high,close\n", "date,low,high,close,turnover,date\n",
                               "date,low,high,close,turnover,\n", "\"date\",low,high,close,turnover\n")
            error = try
                read_bars(IOBuffer(invalid_header * row);
                          price_basis=:unadjusted, turnover_basis=:float_shares)
                nothing
            catch caught
                caught
            end
            @test error isa ArgumentError
            @test occursin("line 1:", sprint(showerror, error))
        end
        for text in ("", "\n \n", header)
            @test_throws ArgumentError read_bars(IOBuffer(text);
                price_basis=:unadjusted, turnover_basis=:float_shares)
        end
        for invalid in ("2000-01-03,8,10,9,0.05\n", "2000-01-02,8,10,9,0.05\n")
            error = try
                read_bars(IOBuffer(header * row * invalid);
                          price_basis=:unadjusted, turnover_basis=:float_shares)
                nothing
            catch caught
                caught
            end
            @test error isa ArgumentError
            @test occursin("line 3:", sprint(showerror, error))
        end
        symbol_header = "date,low,high,close,turnover,symbol,vwap\n"
        for text in (
            symbol_header * "2000-01-03,8,10,9,0.05,,9\n",
            symbol_header * "2000-01-03,8,10,9,0.05,000001,NaN\n",
            symbol_header * "2000-01-03,8,10,9,0.05,000001,12\n",
            symbol_header * "2000-01-03,8,10,9,0.05,000001,9\n" *
                            "2000-01-04,8,10,9,0.05,000002,9\n",
        )
            @test_throws ArgumentError read_bars(IOBuffer(text);
                price_basis=:unadjusted, turnover_basis=:float_shares)
        end
        @test_throws ArgumentError read_bars(IOBuffer(symbol_header * "2000-01-03,8,10,9,0.05,000001,9\n");
            price_basis=:unadjusted, turnover_basis=:float_shares, symbol="000002")
        @test_throws ArgumentError read_bars(IOBuffer(header * row);
            price_basis=:unadjusted, turnover_basis=:float_shares, turnover_unit=:guess)
        @test_throws ArgumentError read_bars(IOBuffer(header * "2000-01-03,8,10,9,-5e-324\n");
            price_basis=:unadjusted, turnover_basis=:float_shares, turnover_unit=:percent)
        invalid_utf8 = IOBuffer(vcat(collect(codeunits(header)), UInt8[0xff], collect(codeunits(row))))
        @test_throws ArgumentError read_bars(invalid_utf8;
            price_basis=:unadjusted, turnover_basis=:float_shares)
        @test isopen(invalid_utf8)
        @test_throws ArgumentError read_bars(IOBuffer(header * row);
            price_basis=:unadjusted, turnover_basis=:float_shares, delimiter='"')
        @test_throws ArgumentError read_bars(IOBuffer(header * row);
            price_basis=:unadjusted, turnover_basis=:float_shares, delimiter=",")
        for columns in ((date=:date,), (date=:date, low=:low, high=:high, close=:close, turnover=:turnover, open=:open),
                        (date=:date, low=:low, high=:high, close=:close, turnover=:close),
                        (date=:date, low=:low, high=:high, close=:close, turnover=""),
                        (date=:date, low=:low, high=:high, close=:close, turnover=nothing),
                        ["date", "low", "high", "close", "turnover"])
            @test_throws ArgumentError read_bars(IOBuffer(header * row);
                price_basis=:unadjusted, turnover_basis=:float_shares, columns)
        end
        # Even unused fields must follow the unquoted-format contract.
        @test_throws ArgumentError read_bars(IOBuffer(header[1:end-1] * ",unused\n" *
            row[1:end-1] * ",\"ignored\"\n"); price_basis=:unadjusted, turnover_basis=:float_shares)
    end
end
