using Dates

@testset "Dated reference histograms and explicit probability units" begin
    @testset "Owned snapshots, dates and basis metadata" begin
        dates = [Date(2000, 1, 3), Date(2000, 1, 4)]
        first = ChipDistribution(PriceGrid([8, 10, 12]), [3, 1])
        second = ChipDistribution(PriceGrid([7, 9, 11, 13]), [0, 1, 1])
        snapshots = [first, second]
        series = ReferenceSeries(dates, snapshots;
                                 price_basis=:unadjusted, symbol=" 000001.SYNTHETIC ")
        @test series.symbol == "000001.SYNTHETIC"
        @test series.price_basis == :unadjusted
        @test trade_dates(series) == dates
        @test bin_edges(series.distributions[2]) == [7, 9, 11, 13]
        @test probabilities(series.distributions[1]) == [0.75, 0.25]
        @test probabilities(series.distributions[2]) == [0, 0.5, 0.5]
        @test series.dates !== dates
        @test series.distributions !== snapshots
        @test series.distributions[1].grid.edges !== first.grid.edges
        @test series.distributions[1].mass !== first.mass
        dates[1] = Date(1999, 1, 1)
        snapshots[1] = second
        first.grid.edges[1] = 0
        first.mass[1] = 0
        copied_dates = trade_dates(series)
        copied_dates[1] = Date(1998, 1, 1)
        @test trade_dates(series)[1] == Date(2000, 1, 3)
        @test bin_edges(series.distributions[1]) == [8, 10, 12]
        @test probabilities(series.distributions[1]) == [0.75, 0.25]

        one = ChipDistribution(PriceGrid([8, 10]), [1])
        fixed = ReferenceSeries([Date(2000, 1, 3)], [one]; price_basis=:fixed_adjusted)
        @test fixed.symbol === nothing
        @test fixed.price_basis == :fixed_adjusted
        @test_throws UndefKeywordError ReferenceSeries([Date(2000, 1, 3)], [one])
        for invalid in (:unknown, "unadjusted", nothing, missing)
            @test_throws ArgumentError ReferenceSeries([Date(2000, 1, 3)], [one]; price_basis=invalid)
        end
        for invalid in ("", "   ", :stock, 1)
            @test_throws ArgumentError ReferenceSeries([Date(2000, 1, 3)], [one];
                                                       price_basis=:unadjusted, symbol=invalid)
        end
        @test_throws ArgumentError ReferenceSeries(Date[], ChipDistribution[]; price_basis=:unadjusted)
        @test_throws ArgumentError ReferenceSeries([Date(2000, 1, 3), Date(2000, 1, 4)], [one];
                                                   price_basis=:unadjusted)
        for invalid in ([Date(2000, 1, 3), Date(2000, 1, 3)],
                        [Date(2000, 1, 4), Date(2000, 1, 3)])
            @test_throws ArgumentError ReferenceSeries(invalid, [one, one]; price_basis=:unadjusted)
        end
    end

    @testset "Fixture, explicit units and varying daily grids" begin
        fixture = joinpath(@__DIR__, "..", "examples", "fixtures", "reference_synthetic.csv")
        series = read_distributions(fixture; price_basis=:unadjusted)
        @test trade_dates(series) == [Date(2000, 1, 3), Date(2000, 1, 4)]
        @test series.symbol == "000001.SYNTHETIC"
        @test probabilities(series.distributions[1]) == [0.75, 0.25]
        @test probabilities(series.distributions[2]) == [0.5, 0.5]
        @test bin_edges(series.distributions[1]) == [8, 10, 12]
        @test average_cost(series.distributions[1]) == 9.5
        @test average_cost(series.distributions[2]) == 10

        header = "date,bin_left,bin_right,mass\n"
        for (unit, values) in ((:fraction, ("0.75", "0.25")),
                               (:percent, ("75", "25")),
                               (:weights, ("3", "1")))
            io = IOBuffer(header * "2000-01-03,8,10,$(values[1])\n" *
                                   "2000-01-03,10,12,$(values[2])\n")
            result = read_distributions(io; price_basis=:fixed_adjusted, mass_unit=unit,
                                         symbol="000001")
            @test result.symbol == "000001"
            @test result.price_basis == :fixed_adjusted
            @test probabilities(result.distributions[1]) == [0.75, 0.25]
            @test isopen(io)
            @test eof(io)
        end
        different = read_distributions(IOBuffer(header *
            "2000-01-03,8,10,0.75\n2000-01-03,10,12,0.25\n" *
            "2000-01-05,7,9,0\n2000-01-05,9,11,0.5\n2000-01-05,11,13,0.5\n");
            price_basis=:unadjusted)
        @test different.symbol === nothing
        @test trade_dates(different) == [Date(2000, 1, 3), Date(2000, 1, 5)]
        @test bin_edges(different.distributions[2]) == [7, 9, 11, 13]
        @test probabilities(different.distributions[2]) == [0, 0.5, 0.5]

        rounded = read_distributions(IOBuffer(header * "2000-01-03,8,10,1.0000005\n");
            price_basis=:unadjusted)
        @test probabilities(rounded.distributions[1]) == [1]
        exact = read_distributions(IOBuffer(header * "2000-01-03,0,1,1\n");
            price_basis=:unadjusted, mass_tolerance=0)
        @test bin_edges(exact.distributions[1]) == [0, 1]
        @test probabilities(exact.distributions[1]) == [1]
        # Explicit weights allow scale-safe normalization despite an overflowing raw sum.
        huge = string(floatmax(Float64))
        weights = read_distributions(IOBuffer(header *
            "2000-01-03,8,10,$huge\n2000-01-03,10,12,$huge\n");
            price_basis=:unadjusted, mass_unit=:weights)
        @test probabilities(weights.distributions[1]) == [0.5, 0.5]
        tiny = read_distributions(IOBuffer(header *
            "2000-01-03,8,10,1e-300\n2000-01-03,10,12,3e-300\n");
            price_basis=:unadjusted, mass_unit=:weights)
        @test probabilities(tiny.distributions[1]) ≈ [0.25, 0.75]
    end

    @testset "Simple format, header mapping and caller-owned IO" begin
        io = IOBuffer("\ufeff\r\n  \r\n date , bin_left , bin_right , mass , symbol , unused \r\n" *
            "2000-01-03,8,10,0.75,000001,ignored\r\n\r\n" *
            "2000-01-03,10,12,0.25,000001,ignored\r\n\r\n")
        result = read_distributions(io; price_basis=:unadjusted)
        @test isopen(io)
        @test eof(io)
        @test result.symbol == "000001"
        @test probabilities(result.distributions[1]) == [0.75, 0.25]
        with_bom = read_distributions(IOBuffer("\ufeffdate,bin_left,bin_right,mass\n2000-01-03,8,10,1\n");
            price_basis=:unadjusted)
        @test trade_dates(with_bom) == [Date(2000, 1, 3)]

        custom = read_distributions(IOBuffer("day;L;R;W;Code;ignored\n" *
            "03/01/2000;8;10;75;600000.SYNTHETIC;example\n" *
            "03/01/2000;10;12;25;600000.SYNTHETIC;example\n");
            price_basis=:unadjusted, mass_unit=:percent, delimiter=';',
            dateformat=dateformat"dd/mm/yyyy", symbol="600000.SYNTHETIC",
            columns=(date=:day, left="L", right=:R, mass="W", symbol=:Code))
        @test trade_dates(custom) == [Date(2000, 1, 3)]
        @test custom.symbol == "600000.SYNTHETIC"
        @test probabilities(custom.distributions[1]) == [0.75, 0.25]
        for columns in ((date=:date, left=:bin_left, right=:bin_right, mass=:mass),
                        (date="date", left="bin_left", right="bin_right", mass="mass", symbol=nothing))
            result = read_distributions(IOBuffer("date,bin_left,bin_right,mass\n2000-01-03,8,10,1\n");
                price_basis=:unadjusted, columns)
            @test result.symbol === nothing
            @test probabilities(result.distributions[1]) == [1]
        end
    end

    @testset "Reject inconsistent probability sums before normalization" begin
        header = "date,bin_left,bin_right,mass\n"
        for (unit, rows) in (
            (:fraction, "2000-01-03,8,10,75\n2000-01-03,10,12,25\n"),
            (:percent, "2000-01-03,8,10,0.75\n2000-01-03,10,12,0.25\n"),
            (:fraction, "2000-01-03,8,10,0.25\n2000-01-03,10,12,0.25\n"),
            (:fraction, "2000-01-03,8,10,1.00001\n2000-01-03,10,12,0\n"),
            (:fraction, "2000-01-03,8,10,0\n2000-01-03,10,12,0\n"),
            (:weights, "2000-01-03,8,10,0\n2000-01-03,10,12,0\n"),
            (:fraction, "2000-01-03,8,10,1.7976931348623157e308\n2000-01-03,10,12,1.7976931348623157e308\n"),
        )
            io = IOBuffer(header * rows * "\n")
            error = try
                read_distributions(io; price_basis=:unadjusted, mass_unit=unit)
                nothing
            catch caught
                caught
            end
            @test error isa ArgumentError
            @test occursin("line 3:", sprint(showerror, error))
            @test isopen(io)
        end
        @test_throws ArgumentError read_distributions(IOBuffer(header * "2000-01-03,8,10,1.0000005\n");
            price_basis=:unadjusted, mass_tolerance=0)
        # A bad completed group is rejected when the next date starts.
        error = try
            read_distributions(IOBuffer(header *
                "2000-01-03,8,10,0.5\n2000-01-04,8,10,1\n"); price_basis=:unadjusted)
            nothing
        catch caught
            caught
        end
        @test error isa ArgumentError
        @test occursin("line 2:", sprint(showerror, error))
        # A positive percent bin must not disappear even if the other bin sums to 100%.
        percent_io = IOBuffer(header *
            "2000-01-03,8,10,100\n2000-01-03,10,12,5e-324\n")
        percent_error = try
            read_distributions(percent_io; price_basis=:unadjusted, mass_unit=:percent)
            nothing
        catch caught
            caught
        end
        @test percent_error isa ArgumentError
        @test occursin("line 3:", sprint(showerror, percent_error))
        @test occursin("underflow", sprint(showerror, percent_error))
        @test isopen(percent_io)

        normalized_error = try
            read_distributions(IOBuffer(header *
                "2000-01-03,8,10,1e308\n2000-01-03,10,12,1e-308\n");
                price_basis=:unadjusted, mass_unit=:weights)
            nothing
        catch caught
            caught
        end
        @test normalized_error isa ArgumentError
        @test occursin("line 3:", sprint(showerror, normalized_error))
    end

    @testset "Reject invalid bins, dates, symbols and physical rows" begin
        header = "date,bin_left,bin_right,mass\n"
        invalid_rows = (
            "2000-01-03,,10,1\n", "2000-01-03,8,,1\n", "2000-01-03,8,10,\n",
            "2000-01-03,8,10,nope\n", "2000-01-03,8,10,NaN\n", "2000-01-03,8,10,Inf\n",
            "2000-01-03,8,10,-1\n", "2000-01-03,NaN,10,1\n", "2000-01-03,8,Inf,1\n",
            "2000-01-03,-1,10,1\n", "2000-01-03,8,8,1\n", "2000-01-03,10,8,1\n",
            "2000-02-30,8,10,1\n", "2000-01,8,10,1\n", "2000-1-3,8,10,1\n",
            ",8,10,1\n", "2000-01-03,8,10,1,extra\n", "2000-01-03,8,10\n",
            "\"2000-01-03\",8,10,1\n",
        )
        for invalid in invalid_rows
            io = IOBuffer("\n" * header * "\n" * invalid)
            error = try
                read_distributions(io; price_basis=:unadjusted)
                nothing
            catch caught
                caught
            end
            @test error isa ArgumentError
            @test occursin("line 4:", sprint(showerror, error))
            @test isopen(io)
        end
        for second in ("2000-01-03,11,12,0.5\n", "2000-01-03,9,12,0.5\n",
                       "2000-01-03,8,10,0.5\n", "2000-01-02,10,12,0.5\n")
            error = try
                read_distributions(IOBuffer(header * "2000-01-03,8,10,0.5\n" * second);
                    price_basis=:unadjusted)
                nothing
            catch caught
                caught
            end
            @test error isa ArgumentError
            @test occursin("line 3:", sprint(showerror, error))
        end
        repeated_group = try
            read_distributions(IOBuffer(header * "2000-01-03,8,10,1\n" *
                "2000-01-04,8,10,1\n2000-01-03,8,10,1\n"); price_basis=:unadjusted)
            nothing
        catch caught
            caught
        end
        @test repeated_group isa ArgumentError
        @test occursin("line 4:", sprint(showerror, repeated_group))

        for invalid in ("date,bin_left,bin_right\n", "date,bin_left,bin_right,mass,date\n",
                        "date,bin_left,bin_right,mass,\n", "\"date\",bin_left,bin_right,mass\n")
            error = try
                read_distributions(IOBuffer(invalid * "2000-01-03,8,10,1\n"); price_basis=:unadjusted)
                nothing
            catch caught
                caught
            end
            @test error isa ArgumentError
            @test occursin("line 1:", sprint(showerror, error))
        end
        for text in ("", "\n  \n", header, header * "\n")
            @test_throws ArgumentError read_distributions(IOBuffer(text); price_basis=:unadjusted)
        end
        symbol_header = header[1:end-1] * ",symbol\n"
        for rows in ("2000-01-03,8,10,1,\n",
                     "2000-01-03,8,10,0.5,000001\n2000-01-03,10,12,0.5,000002\n",
                     "2000-01-03,8,10,1,000001\n2000-01-04,8,10,1,000002\n")
            @test_throws ArgumentError read_distributions(IOBuffer(symbol_header * rows); price_basis=:unadjusted)
        end
        @test_throws ArgumentError read_distributions(IOBuffer(symbol_header * "2000-01-03,8,10,1,000001\n");
            price_basis=:unadjusted, symbol="000002")
        @test_throws ArgumentError read_distributions(IOBuffer(header[1:end-1] *
            ",unused\n2000-01-03,8,10,1,\"quoted\"\n"); price_basis=:unadjusted)
        invalid_utf8 = IOBuffer(vcat(Vector{UInt8}(codeunits(header)), [0xff, 0x0a]))
        @test_throws ArgumentError read_distributions(invalid_utf8; price_basis=:unadjusted)
        @test isopen(invalid_utf8)
    end

    @testset "Invalid declaration and column mappings" begin
        valid = "date,bin_left,bin_right,mass\n2000-01-03,8,10,1\n"
        @test_throws UndefKeywordError read_distributions(IOBuffer(valid))
        for invalid in (:unknown, "unadjusted", nothing, missing)
            @test_throws ArgumentError read_distributions(IOBuffer(valid); price_basis=invalid)
        end
        for invalid in (:unknown, "fraction", nothing, missing)
            @test_throws ArgumentError read_distributions(IOBuffer(valid);
                price_basis=:unadjusted, mass_unit=invalid)
        end
        for invalid in (-1, NaN, Inf, nothing, "small")
            @test_throws ArgumentError read_distributions(IOBuffer(valid);
                price_basis=:unadjusted, mass_tolerance=invalid)
        end
        for invalid in ('"', '\n', '\r', ",", nothing)
            @test_throws ArgumentError read_distributions(IOBuffer(valid);
                price_basis=:unadjusted, delimiter=invalid)
        end
        for invalid in ("", " ", :stock, 1)
            @test_throws ArgumentError read_distributions(IOBuffer(valid);
                price_basis=:unadjusted, symbol=invalid)
        end
        for invalid in ((date=:date, left=:bin_left, right=:bin_right),
                        (date=:date, left=:bin_left, right=:bin_right, mass=:mass, extra=:extra),
                        (date=:date, left=:bin_left, right=:bin_right, mass=:mass, symbol=:mass),
                        (date=:date, left=nothing, right=:bin_right, mass=:mass),
                        (date=:date, left=:bin_left, right=:bin_right, mass=""),
                        (date=:date, left=:bin_left, right=:bin_right, mass=1),
                        Dict(:date => :date))
            @test_throws ArgumentError read_distributions(IOBuffer(valid);
                price_basis=:unadjusted, columns=invalid)
        end
    end
end
