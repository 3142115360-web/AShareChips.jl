@testset "Iterable inputs and allocation-path equivalence" begin
    grid=PriceGrid([8,10,12])
    bars=[DailyBar(low=9,high=9,close=9,turnover=.2),
          DailyBar(low=11,high=11,close=11,turnover=.3)]
    expected=probabilities(chip_distribution(bars;grid))
    @test probabilities(chip_distribution((b for b in bars);grid)) ≈ expected
    @test probabilities(chip_distribution(view(bars,:);grid)) ≈ expected
    @test probabilities(chip_distribution(bars;grid,model=[TriangularModel(),TriangularModel()])) ≈ expected
    @test probabilities(chip_distribution(bars;grid,
        adjustments=(PriceAdjustment() for _ in bars))) ≈ expected
    snapshots=chip_history(bars;grid)
    @test probabilities(snapshots[end]) ≈ expected
    @test probabilities(snapshots[1]) == [1,0]
    @test bars[1].turnover == .2
    @test_throws ArgumentError effective_turnover(LinearTurnover(k=1e-300),1e-300)
    @test_throws ArgumentError effective_turnover(ExponentialTurnover(k=1e-300),1e-300)
end
