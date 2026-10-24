using Test, AShareCostDistributions, TOML
isdefined(@__MODULE__, :analyze_csv) ||
    include(joinpath(@__DIR__, "..", "examples", "analyze_csv.jl"))

@testset "Independent numerical boundary regressions" begin
    @testset "A tiny remote tail still has a finite transport cost" begin
        grid = PriceGrid([0.0, 1.0, 1.0e308, 1.6e308])
        estimate = ChipDistribution(grid, [1.0, 0.0, 1.0e-300])
        reference = ChipDistribution(grid, [1.0, 0.0, 0.0])
        result = compare_distributions(estimate, reference)
        # Move a 1e-300 tail from the low bin to the remote uniform bin.
        # The distributions are stochastically ordered, so W1 equals the
        # mean difference; rounding a full CDF to 1 must not erase transport.
        @test result.max_cdf_error ≈ 1.0e-300 rtol=1e-12 atol=0
        @test result.wasserstein1 ≈ 1.3e8 rtol=1e-12
        @test result.wasserstein1 ≈ abs(result.mean_cost_error) rtol=1e-12

        # Here both CDF and survival probability are near 0.5. Adding the
        # tiny middle weight changes the normalization of both large bins;
        # two independently rounded accumulations would still agree.
        middle_grid = PriceGrid([0.0, 1.0, 1.0e308, 1.6e308, 1.7e308])
        middle_estimate = ChipDistribution(middle_grid, [0.5, 0, 1e-300, 0.5])
        middle = compare_distributions(
            middle_estimate,
            ChipDistribution(middle_grid, [0.5, 0, 0, 0.5]))
        @test middle.max_cdf_error ≈ 5e-301 rtol=1e-12 atol=0
        @test middle.wasserstein1 ≈ 6.75e7 rtol=1e-12
        @test middle.mean_cost_error ≈ 4.75e7 rtol=1e-12
        @test cost_quantile(middle_estimate, 0.5) ≈ 1.3e308 rtol=1e-12
    end

    @testset "Do not silently erase positive mass through underflow" begin
        grid = PriceGrid([0, 1, 2, 3])
        @test_throws ArgumentError ChipDistribution(grid, [1.0e308, 0, 1.0e-100])
        @test_throws ArgumentError ChipDistribution(grid, [1, 1, nextfloat(0.0)])
        @test_throws ArgumentError ChipDistribution(PriceGrid([0, 1, 2]),
                                                   [big"1", big"1e-1000"])
        source = ChipDistribution(PriceGrid([0, 1, 2]), [1, nextfloat(0.0)])
        @test_throws ArgumentError rebase(source, PriceAdjustment();
                                         grid=PriceGrid([0, 1, 1.5, 2]))
        @test_throws ArgumentError update_chips(source,
            ChipDistribution(source.grid, [1, 0]), 0.5)
        @test_throws ArgumentError DailyBar(low=1, high=2, close=1.5,
                                            turnover=-big"1e-1000")
        header = "date,low,high,close,turnover\n"
        @test_throws ArgumentError read_bars(IOBuffer(header * "2000-01-03,1,2,1.5,5e-324\n");
            price_basis=:unadjusted, turnover_basis=:float_shares, turnover_unit=:percent)
        @test_throws ArgumentError read_bars(IOBuffer(header * "2000-01-03,1,2,1.5,1e-1000\n");
            price_basis=:unadjusted, turnover_basis=:float_shares)
    end

    @testset "Integrate the last triangular bin without CDF cancellation" begin
        right = prevfloat(2.0)
        bar = DailyBar(low=1, high=2, close=1, turnover=0.1)
        distribution = daily_distribution(TriangularModel(peak=:close),
                                           PriceGrid([1.0, right, 2.0]), bar)
        # For the decreasing unit triangle, P(right < p < 2) = (2-right)^2.
        @test probabilities(distribution)[2] ≈ (2-right)^2 rtol=1e-12 atol=0
        @test cost_quantile(distribution, 1) == 2.0
    end
end

@testset "A failed report writer leaves no partial output" begin
    mktempdir() do folder
        output = joinpath(folder, "result.csv")
        @test_throws ErrorException _atomic_output(output) do io
            println(io, "partial row")
            error("simulated report write failure")
        end
        @test !ispath(output)
        @test isempty(readdir(folder))
    end
end

@testset "Grid agreement cannot validate data units" begin
    input = "date,low,high,close,turnover\n" *
            "2000-01-03,9,11,10,5\n2000-01-04,19,21,20,5\n"
    wrong = read_bars(IOBuffer(input); price_basis=:unadjusted,
                     turnover_basis=:float_shares, turnover_unit=:fraction)
    correct = read_bars(IOBuffer(input); price_basis=:unadjusted,
                       turnover_basis=:float_shares, turnover_unit=:percent)
    grids = [PriceGrid(collect(8:0.5:22)), PriceGrid(collect(8:0.1:22))]
    @test all(row -> row.wasserstein1 == 0,
              grid_convergence(wrong, grids; model=UniformModel()))
    @test average_cost(chip_distribution(wrong; grid=last(grids), model=UniformModel())) ≈ 20
    @test average_cost(chip_distribution(correct; grid=last(grids), model=UniformModel())) ≈ 10.5
end

@testset "Report paths reject existing links and directories" begin
    mktempdir() do folder
        input = joinpath(folder, "input.csv")
        cp(joinpath(@__DIR__, "..", "examples", "fixtures", "daily_synthetic.csv"), input)
        original = read(input)
        config_path = joinpath(folder, "analysis.toml")
        configuration = Dict("input" => input, "turnover_unit" => "percent",
            "price_basis" => "unadjusted", "turnover_basis" => "float_shares",
            "grid" => Dict("lower" => 8.0, "upper" => 14.0, "step" => 0.02))
        output_paths = [joinpath(folder, kind * ".csv")
                        for kind in ("hardlink", "directory")]
        hardlink(input, output_paths[1])
        mkdir(output_paths[2])
        future = joinpath(folder, "future.csv")
        dangling = joinpath(folder, "dangling.csv")
        # Creating symlinks can require privileges or Developer Mode on Windows.
        # Hardlinks, directories and atomic writes are checked on every platform;
        # Unix runners additionally exercise live and dangling symlink guards.
        if !Sys.iswindows()
            linked = joinpath(folder, "symlink.csv")
            symlink(input, linked)
            symlink(future, dangling)
            append!(output_paths, [linked, dangling])
        end
        for output in output_paths
            configuration["output"] = output
            open(io -> TOML.print(io, configuration), config_path, "w")
            @test_throws ArgumentError analyze_csv(config_path)
        end
        @test read(input) == original
        if !Sys.iswindows()
            @test !ispath(future)
            @test islink(dangling)
        end
    end
end
