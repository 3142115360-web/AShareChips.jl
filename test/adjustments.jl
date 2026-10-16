using Dates

@testset "Explicit dated cost adjustment import" begin
    dates = [Date(2000, 1, 3), Date(2000, 1, 4), Date(2000, 1, 6)]
    bars = [DailyBar(low=10, high=10, close=10, turnover=0),
            DailyBar(low=5, high=5, close=5, turnover=0),
            DailyBar(low=6, high=6, close=6, turnover=0.25)]
    series = BarSeries(dates, bars; price_basis=:unadjusted,
                       turnover_basis=:float_shares, symbol="000001.SYNTHETIC")
    anonymous = BarSeries(dates, bars; price_basis=:unadjusted,
                          turnover_basis=:float_shares)
    fixed = BarSeries(dates, bars; price_basis=:fixed_adjusted,
                      turnover_basis=:float_shares, symbol=series.symbol)
    text = "date,scale,shift,symbol\n2000-01-04,0.5,0,000001.SYNTHETIC\n"

    @testset "Sparse events align by date and act before turnover" begin
        io = IOBuffer(text)
        changes = read_adjustments(io, series)
        @test changes isa Vector{PriceAdjustment}
        @test length(changes) == 3
        @test [a.scale for a in changes] == [1, 0.5, 1]
        @test [a.shift for a in changes] == [0, 0, 0]
        @test eof(io)
        @test isopen(io)
        grid = PriceGrid([4, 5, 6, 7, 10, 11, 12])
        history = chip_history(series; grid, adjustments=changes)
        @test probabilities(history[1]) == [0, 0, 0, 0, 1, 0]
        @test probabilities(history[2]) == [0, 1, 0, 0, 0, 0]
        @test probabilities(history[3]) ≈ [0, 0.75, 0.25, 0, 0, 0]
        @test average_cost(history[3]) ≈ 5.75
        generated = chip_distribution(series; grid, adjustments=(a for a in changes))
        @test probabilities(generated) ≈ probabilities(history[end])
        @test series.dates == dates
        @test series.bars == bars
        fresh = read_adjustments(IOBuffer(text), series)
        changes[1] = PriceAdjustment(shift=-1)
        @test fresh[1].shift == 0
        @test fresh !== changes
        mktemp() do path, file
            write(file, text)
            close(file)
            loaded = read_adjustments(path, series)
            @test [a.scale for a in loaded] == [1, 0.5, 1]
        end
        fixture = joinpath(@__DIR__, "..", "examples", "fixtures", "events_synthetic.csv")
        @test [a.scale for a in read_adjustments(fixture, series)] == [1, 0.5, 1]
    end

    @testset "Header-only identity, custom fields, BOM and CRLF" begin
        for source in ("date,scale,shift", "date,scale,shift,symbol\n\n",
                       "\ufeff\r\n\r\ndate,scale,shift\r\n\r\n")
            for input in (series, anonymous, fixed)
                changes = read_adjustments(IOBuffer(source), input)
                @test length(changes) == length(input.bars)
                @test all(a -> a.scale == 1 && a.shift == 0, changes)
            end
        end
        plain = read_adjustments(IOBuffer("date,scale,shift\n2000-01-06,1,-0.25\n"), anonymous)
        @test [a.shift for a in plain] == [0, 0, -0.25]
        custom = "\ufeff day | factor | offset | code | note\r\n\r\n" *
                 "20000104 | 0.5 | 0 | 000001.SYNTHETIC | arbitrary\r\n"
        mapped = read_adjustments(IOBuffer(custom), series;
            columns=(date=" day ", scale=:factor, shift=:offset, symbol=:code),
            dateformat=dateformat"yyyymmdd", delimiter='|')
        @test [a.scale for a in mapped] == [1, 0.5, 1]
        @test all(a -> a.shift == 0, mapped)
        identity = read_adjustments(IOBuffer("date,scale,shift,symbol\n" *
            "2000-01-04,1,0,000001.SYNTHETIC\n"), fixed)
        @test all(a -> a.scale == 1 && a.shift == 0, identity)
        # Explicitly omitting a symbol mapping is a caller assertion of ownership.
        for columns in ((date=:date, scale=:scale, shift=:shift),
                        (date=:date, scale=:scale, shift=:shift, symbol=nothing))
            omitted = read_adjustments(IOBuffer(text), anonymous; columns)
            @test omitted[2].scale == 0.5
        end
    end

    @testset "First event is valid input and requires a simulation prior" begin
        first_events = read_adjustments(IOBuffer("date,scale,shift\n2000-01-03,0.5,0\n"), series)
        @test first_events[1].scale == 0.5
        grid = PriceGrid([4, 5, 6, 8, 10, 12])
        @test_throws ArgumentError chip_distribution(series; grid, adjustments=first_events)
        prior = ChipDistribution(grid, [0, 0, 0, 1, 0])
        first_history = chip_history(series; grid, initial=prior, adjustments=first_events)
        @test probabilities(first_history[1]) ≈ [1, 0, 0, 0, 0]
        @test probabilities(prior) == [0, 0, 0, 1, 0]
    end

    @testset "Reject malformed dates, factors, symbols and framing with physical lines" begin
        cases = [
            ("", 1, "header"),
            ("\ufeff\n\n ", 3, "header"),
            ("date,scale\n", 1, "missing required column shift"),
            ("date,shift\n", 1, "missing required column scale"),
            ("scale,shift\n", 1, "missing required column date"),
            ("date,scale,shift,date\n", 1, "duplicate header"),
            ("date,scale,\n", 1, "header names"),
            ("date,scale,shift\n2000-01-04,0.5\n", 2, "row width"),
            ("date,scale,shift\n2000-01-04,0.5,0,unused\n", 2, "row width"),
            ("date,scale,shift\n,0.5,0\n", 2, "date must not be empty"),
            ("date,scale,shift\n2000-1-04,0.5,0\n", 2, "dateformat"),
            ("date,scale,shift\n2000-01,0.5,0\n", 2, "dateformat"),
            ("date,scale,shift\n2000-02-31,0.5,0\n", 2, "dateformat"),
            ("date,scale,shift\n1999-12-31,0.5,0\n", 2, "no matching observation"),
            ("date,scale,shift\n2000-01-05,0.5,0\n", 2, "no matching observation"),
            ("date,scale,shift\n2000-01-07,0.5,0\n", 2, "no matching observation"),
            ("date,scale,shift\n2000-01-04,1,0\n2000-01-04,1,0\n", 3, "strictly increasing"),
            ("date,scale,shift\n2000-01-06,1,0\n\n2000-01-04,1,0\n", 4, "strictly increasing"),
            ("date,scale,shift\n2000-01-04,,0\n", 2, "scale must not be empty"),
            ("date,scale,shift\n2000-01-04,1,\n", 2, "shift must not be empty"),
            ("date,scale,shift\n2000-01-04,0,0\n", 2, "scale must be positive"),
            ("date,scale,shift\n2000-01-04,-0.5,0\n", 2, "scale must be positive"),
            ("date,scale,shift\n2000-01-04,NaN,0\n", 2, "scale must be a finite number"),
            ("date,scale,shift\n2000-01-04,Inf,0\n", 2, "scale must be a finite number"),
            ("date,scale,shift\n2000-01-04,invalid,0\n", 2, "scale must be a finite number"),
            ("date,scale,shift\n2000-01-04,1,NaN\n", 2, "shift must be a finite number"),
            ("date,scale,shift\n2000-01-04,1,-Inf\n", 2, "shift must be a finite number"),
            ("date,scale,shift\n2000-01-04,1,1e400\n", 2, "shift must be a finite number"),
            ("date,scale,shift,symbol\n2000-01-04,1,0,\n", 2, "symbol must not be empty"),
            ("date,scale,shift,symbol\n2000-01-04,1,0,000002.SYNTHETIC\n", 2, "symbol does not match"),
            ("date,scale,shift,symbol\n2000-01-03,1,0,000001.SYNTHETIC\n" *
             "2000-01-04,1,0,000002.SYNTHETIC\n", 3, "symbol does not match"),
            ("date,scale,shift\n2000-01-04,\"1\",0\n", 2, "quoted fields"),
            ("date,scale,shift,note\n2000-01-04,1,0,\"unused\"\n", 2, "quoted fields"),
            ("\n\ufeffdate,scale,shift\n", 2, "missing required column date"),
        ]
        for (source, line, message) in cases
            io = IOBuffer(source)
            error = try
                read_adjustments(io, series)
                nothing
            catch caught
                caught
            end
            @test error isa ArgumentError
            @test occursin("line $line:", sprint(showerror, error))
            @test occursin(message, sprint(showerror, error))
            @test isopen(io)
        end
        for (input, source, fragment) in (
            (anonymous, text, "series.symbol must be specified"),
            (fixed, text, "fixed-adjusted"),
            (fixed, "date,scale,shift\n2000-01-04,1,-0.1\n", "fixed-adjusted"),
        )
            error = try
                read_adjustments(IOBuffer(source), input)
                nothing
            catch caught
                caught
            end
            @test error isa ArgumentError
            @test occursin("line 2:", sprint(showerror, error))
            @test occursin(fragment, sprint(showerror, error))
        end
        for source in (UInt8[0xff, 0x0a],
                       vcat(codeunits("date,scale,shift,note\n2000-01-04,1,0,"), UInt8[0xff, 0x0a]),
                       vcat(codeunits("date,scale,shift\n\n"), UInt8[0xff, 0x0a]))
            error = try
                read_adjustments(IOBuffer(source), series)
                nothing
            catch caught
                caught
            end
            @test error isa ArgumentError
            @test occursin("UTF-8", sprint(showerror, error))
            @test occursin("line", sprint(showerror, error))
        end
    end

    @testset "Column mapping and delimiter validation" begin
        for invalid in ((date=:date, scale=:scale),
                        (date=:date, scale=:scale, shift=:shift, unknown=:x),
                        (date=:date, scale=:scale, shift=:scale),
                        (date=:date, scale=" ", shift=:shift),
                        (date=:date, scale=nothing, shift=:shift),
                        (date=:date, scale=:scale, shift=:shift, symbol=1),
                        (:date, :scale, :shift))
            @test_throws ArgumentError read_adjustments(IOBuffer(text), series; columns=invalid)
        end
        for delimiter in ('"', '\n', '\r', ",", nothing)
            @test_throws ArgumentError read_adjustments(IOBuffer(text), series; delimiter)
        end
    end
end
