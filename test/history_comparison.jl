using Dates
@testset "Date and security aligned reference comparison" begin
    dates=[Date(2000,1,3),Date(2000,1,4),Date(2000,1,5)]
    bars=[DailyBar(low=9,high=9,close=9,turnover=0),
          DailyBar(low=11,high=11,close=11,turnover=.25),
          DailyBar(low=9,high=9,close=9,turnover=.5)]
    series=BarSeries(dates,bars;price_basis=:unadjusted,turnover_basis=:float_shares,symbol="TEST.SYNTHETIC")
    grid=PriceGrid([8,10,12])
    references=ReferenceSeries(dates[1:2],
        [ChipDistribution(grid,[1,0]),ChipDistribution(grid,[3,1])];
        price_basis=:unadjusted,symbol=series.symbol)
    @test_throws ArgumentError compare_history(series,references;grid)
    result=compare_history(series,references;grid,matching=:intersection)
    @test length(result.rows)==2
    @test result.estimate_only_dates==[dates[3]]
    @test isempty(result.reference_only_dates)
    @test result.symbol==series.symbol
    @test result.price_basis==:unadjusted
    @test all(row->row.wasserstein1==0,result.rows)
    @test all(row->row.mean_cost_error==0,result.rows)
    @test result.rows[1].prices==[9]
    @test result.rows[2].prices==[11]
    @test result.rows[2].profit_errors==[0]
    @test result.rows[2].quantile_errors==zeros(3)
    full=ReferenceSeries(dates,chip_history(series;grid);price_basis=:unadjusted,symbol=series.symbol)
    strict=compare_history(series,full;grid,quantiles=(q for q in (0,.5,1)),prices=(p for p in (9,11)))
    @test length(strict.rows)==3
    @test all(row->row.prices==[9,11],strict.rows)
    @test strict.rows[1].prices !== strict.rows[2].prices
    @test all(row->row.max_cdf_error==0,strict.rows)
    wrong_symbol=ReferenceSeries(references.dates,references.distributions;price_basis=:unadjusted,symbol="OTHER")
    @test_throws ArgumentError compare_history(series,wrong_symbol;grid,matching=:intersection,require_symbol_match=false)
    wrong_basis=ReferenceSeries(references.dates,references.distributions;price_basis=:fixed_adjusted,symbol=series.symbol)
    @test_throws ArgumentError compare_history(series,wrong_basis;grid,matching=:intersection)
    unknown=ReferenceSeries(references.dates,references.distributions;price_basis=:unadjusted)
    @test_throws ArgumentError compare_history(series,unknown;grid,matching=:intersection)
    @test length(compare_history(series,unknown;grid,matching=:intersection,require_symbol_match=false).rows)==2
    missing=ReferenceSeries([Date(2000,1,6)],[ChipDistribution(grid,[1,0])];price_basis=:unadjusted,symbol=series.symbol)
    @test_throws ArgumentError compare_history(series,missing;grid,matching=:intersection)
    @test_throws ArgumentError compare_history(series,full;grid,matching=:automatic)
    @test_throws ArgumentError compare_history(series,full;grid,quantiles=[NaN])
    @test_throws ArgumentError compare_history(series,full;grid,prices=[Inf])
    # Missing reference days remain in the recursive simulation.
    last_only=ReferenceSeries(dates[3:3],[ChipDistribution(grid,[7,1])];price_basis=:unadjusted,symbol=series.symbol)
    @test compare_history(series,last_only;grid,matching=:intersection).rows[1].wasserstein1==0
end
