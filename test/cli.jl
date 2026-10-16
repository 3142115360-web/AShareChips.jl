using Test, TOML
include(joinpath(@__DIR__,"..","examples","analyze_csv.jl"))
const fixture=abspath(joinpath(@__DIR__,"..","examples","fixtures","daily_synthetic.csv"))
@testset "File analysis example" begin
    mktempdir() do folder
        config_path=joinpath(folder,"analysis.toml")
        output=joinpath(folder,"result.csv")
        configuration=Dict("input"=>fixture,"output"=>output,"turnover_unit"=>"percent",
            "price_basis"=>"unadjusted","turnover_basis"=>"float_shares",
            "grid"=>Dict("lower"=>8.0,"upper"=>14.0,"step"=>0.02))
        open(io->TOML.print(io,configuration),config_path,"w")
        @test analyze_csv(config_path)==output
        lines=readlines(output)
        @test length(lines)==4
        @test split(lines[1],',')[5]=="profit_fraction"
        @test split(lines[2],',')[1:3]==["2000-01-03","000001.SYNTHETIC","10.0"]
        @test parse(Float64,split(lines[2],',')[4]) ≈ 10.0
        @test parse(Float64,split(lines[2],',')[5]) ≈ 0.5
        @test_throws ArgumentError analyze_csv(config_path)
        @test length(readlines(output))==4
        configuration["output"]=fixture
        open(io->TOML.print(io,configuration),config_path,"w")
        @test_throws ArgumentError analyze_csv(config_path)
        @test length(readlines(fixture))==4
        configuration["output"]=joinpath(folder,"invalid.csv")
        configuration["report"]=Dict("coverage"=>0.0)
        open(io->TOML.print(io,configuration),config_path,"w")
        @test_throws ArgumentError analyze_csv(config_path)
        @test !isfile(configuration["output"])
        configuration["report"]=Dict("coverage"=>0.9)
        configuration["grid"]["step"]=0
        open(io->TOML.print(io,configuration),config_path,"w")
        @test_throws ArgumentError analyze_csv(config_path)
        @test !isfile(configuration["output"])
        @test _report_cell("A,B")=="\"A,B\""
    end
end

@testset "Analysis integrates references before publishing reports" begin
    mktempdir() do folder
        input=joinpath(folder,"daily.csv")
        reference=joinpath(folder,"reference.csv")
        output=joinpath(folder,"daily-result.csv")
        comparison=joinpath(folder,"comparison-result.csv")
        config_path=joinpath(folder,"config.toml")
        cp(fixture,input)
        cp(joinpath(@__DIR__,"..","examples","fixtures","reference_synthetic.csv"),reference)
        config=Dict("input"=>input,"output"=>output,"turnover_unit"=>"percent",
            "price_basis"=>"unadjusted","turnover_basis"=>"float_shares",
            "grid"=>Dict("lower"=>8.0,"upper"=>14.0,"step"=>.02),
            "comparison"=>Dict("input"=>reference,"output"=>comparison,"price_basis"=>"unadjusted",
                                "mass_unit"=>"fraction","matching"=>"strict"))
        open(io->TOML.print(io,config),config_path,"w")
        @test_throws ArgumentError analyze_csv(config_path)
        @test !ispath(output)
        @test !ispath(comparison)
        config["comparison"]["matching"]="intersection"
        open(io->TOML.print(io,config),config_path,"w")
        @test analyze_csv(config_path)==output
        @test length(readlines(output))==4
        lines=readlines(comparison)
        @test length(lines)==3
        @test split(lines[2],',')[1]=="2000-01-03"
        @test parse(Float64,split(lines[2],',')[6]) ≈ .5
        # The model differs from a handmade reference; success is not equality.
        @test parse(Float64,split(lines[2],',')[4]) > 0
    end
end

@testset "Event configuration is applied before the daily update" begin
    mktempdir() do folder
        input,events=joinpath(folder,"daily.csv"),joinpath(folder,"events.csv")
        output,config_path=joinpath(folder,"result.csv"),joinpath(folder,"config.toml")
        write(input,"date,low,high,close,turnover,symbol\n2000-01-03,8,10,9,0,TEST.SYNTHETIC\n2000-01-04,4,5,4.5,0,TEST.SYNTHETIC\n")
        write(events,"date,scale,shift,symbol\n2000-01-04,0.5,0,TEST.SYNTHETIC\n")
        config=Dict("input"=>input,"output"=>output,"events"=>events,"turnover_unit"=>"fraction",
            "price_basis"=>"unadjusted","turnover_basis"=>"float_shares",
            "grid"=>Dict("lower"=>4.0,"upper"=>10.0,"step"=>1.0),"model"=>Dict("kind"=>"uniform"))
        open(io->TOML.print(io,config),config_path,"w")
        @test analyze_csv(config_path)==output
        lines=readlines(output)
        @test parse(Float64,split(lines[3],',')[4]) ≈ 4.5
        @test parse(Float64,split(lines[3],',')[5]) ≈ .5
        config["output"]=joinpath(folder,"fixed-result.csv")
        config["price_basis"]="fixed_adjusted"
        open(io->TOML.print(io,config),config_path,"w")
        @test_throws ArgumentError analyze_csv(config_path)
        @test !ispath(config["output"])
    end
end
