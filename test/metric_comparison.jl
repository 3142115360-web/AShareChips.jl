using Test
using AShareCostDistributions

@testset "Scalar summary comparison" begin
    asymmetric = ChipDistribution(PriceGrid([1,2,4]), [.75,.25])
    uniform = ChipDistribution(PriceGrid([1,3]), [1])

    @testset "Independent asymmetric histogram oracle" begin
        # Integrating 3/4 on [1,2] and 1/4 on [2,4] gives mean 15/8,
        # median 5/3 and F(5/2)=13/16. The median is not the mean.
        result = compare_metrics(asymmetric; mean_cost=15/8,
            quantiles=[.05,.15,.5,.85,.95],
            quantile_costs=[16/15,6/5,5/3,14/5,18/5],
            prices=[5/2], profit_ratios=[13/16])
        @test result.mean_cost_estimate == 15/8
        @test result.mean_cost_reference == 15/8
        @test result.mean_cost_error == 0
        @test result.quantile_estimates ≈ [16/15,6/5,5/3,14/5,18/5]
        @test result.quantile_references == [16/15,6/5,5/3,14/5,18/5]
        @test result.quantile_errors ≈ zeros(5) atol=1e-14
        @test result.quantile_estimates[3] != result.mean_cost_estimate
        @test result.profit_estimates == [13/16]
        @test result.profit_references == [13/16]
        @test result.profit_errors == [0]
        @test keys(result) == (:mean_cost_estimate,:mean_cost_reference,:mean_cost_error,
            :quantiles,:quantile_estimates,:quantile_references,:quantile_errors,
            :prices,:profit_estimates,:profit_references,:profit_errors)
        @test !haskey(result,:wasserstein1)
        @test !haskey(result,:max_cdf_error)
    end

    @testset "Translated uniform summaries and error direction" begin
        # Reference is uniform on [1.2,3.2], specified only through summaries.
        result = compare_metrics(uniform; mean_cost=2.2,
            quantiles=[.05,.5,.95], quantile_costs=[1.3,2.2,3.1],
            prices=[2.5], profit_ratios=[.65])
        @test result.mean_cost_error ≈ -.2
        @test result.quantile_estimates ≈ [1.1,2,2.9]
        @test result.quantile_errors ≈ fill(-.2,3)
        @test result.profit_estimates == [.75]
        @test result.profit_errors ≈ [.1]
    end

    @testset "Single summary modes, explicit units and support endpoints" begin
        mean_only = compare_metrics(asymmetric; mean_cost=0)
        @test mean_only.mean_cost_reference == 0
        @test mean_only.mean_cost_error == 15/8
        @test isempty(mean_only.quantiles)
        @test isempty(mean_only.quantile_estimates)
        @test isempty(mean_only.profit_errors)
        quantile_only = compare_metrics(uniform; quantiles=[0,1],quantile_costs=[0,3])
        @test quantile_only.mean_cost_estimate === nothing
        @test quantile_only.mean_cost_reference === nothing
        @test quantile_only.mean_cost_error === nothing
        @test quantile_only.quantile_estimates == [1,3]
        @test quantile_only.quantile_errors == [1,0]
        @test isempty(quantile_only.prices)
        fraction = compare_metrics(asymmetric; prices=[2.5],profit_ratios=[.8125])
        percent = compare_metrics(asymmetric; prices=[2.5],profit_ratios=[81.25],profit_unit=:percent)
        @test percent == fraction
        endpoints = compare_metrics(uniform;
            prices=[-1,0,1,3,4],profit_ratios=[0,0,0,100,100],profit_unit=:percent)
        @test endpoints.profit_estimates == [0,0,0,1,1]
        @test endpoints.profit_references == [0,0,0,1,1]
        @test endpoints.profit_errors == zeros(5)
        @test isempty(endpoints.quantile_errors)
        @test endpoints.mean_cost_error === nothing
    end

    @testset "Ordering, duplicate consistency and independent ownership" begin
        qs, qref = [.95,.05,.5,.05], [3.6,16/15,5/3,16/15]
        ps, pref = [2.5,1,2.5], [.8125,0,.8125]
        mass, edges = probabilities(asymmetric), bin_edges(asymmetric)
        result = compare_metrics(asymmetric;
            quantiles=qs,quantile_costs=qref,prices=ps,profit_ratios=pref)
        @test result.quantiles == qs
        @test result.quantile_references == qref
        @test result.quantile_estimates ≈ [3.6,16/15,5/3,16/15]
        @test result.quantile_errors ≈ zeros(4) atol=1e-14
        @test result.prices == ps
        @test result.profit_estimates == [.8125,0,.8125]
        @test result.profit_errors == zeros(3)
        for values in (qs,qref,ps,pref)
            values[1] = 99
        end
        @test result.quantiles[1] == .95
        @test result.quantile_references[1] == 3.6
        @test result.prices[1] == 2.5
        @test result.profit_references[1] == .8125
        # All returned vector fields own their values, even if inputs alias.
        for values in (result.quantiles,result.quantile_estimates,result.quantile_references,
                       result.quantile_errors,result.prices,result.profit_estimates,
                       result.profit_references,result.profit_errors)
            values[1] = 88
        end
        @test qs[2] == .05
        @test qref[2] == 16/15
        @test ps[2] == 1
        @test pref[2] == 0
        @test probabilities(asymmetric) == mass
        @test bin_edges(asymmetric) == edges
        alias = [.5]
        aliased_result = compare_metrics(uniform;
            quantiles=alias,quantile_costs=alias,prices=alias,profit_ratios=alias)
        aliased_result.quantiles[1] = .1
        @test aliased_result.quantile_references == [.5]
        @test aliased_result.prices == [.5]
        @test aliased_result.profit_references == [.5]
        @test alias == [.5]
        equal_costs = compare_metrics(uniform;
            quantiles=[.9,.1,.5],quantile_costs=[2,2,2])
        @test equal_costs.quantile_references == [2,2,2]
    end

    @testset "Single consumption of summary iterators" begin
        qc, cc, pc, rc = Ref(0), Ref(0), Ref(0), Ref(0)
        result = compare_metrics(uniform;
            quantiles=((qc[] += 1; v) for v in (0,.5,1)),
            quantile_costs=((cc[] += 1; v) for v in (1,2,3)),
            prices=((pc[] += 1; v) for v in (1,2,3)),
            profit_ratios=((rc[] += 1; v) for v in (0,.5,1)))
        @test (qc[],cc[],pc[],rc[]) == (3,3,3,3)
        @test result.quantiles == [0,.5,1]
        @test result.quantile_errors == zeros(3)
        @test result.prices == [1,2,3]
        @test result.profit_errors == zeros(3)
    end

    @testset "Invalid summaries cannot be silently normalized" begin
        @test_throws ArgumentError compare_metrics(uniform)
        @test_throws ArgumentError compare_metrics(uniform; mean_cost=nothing,
            quantiles=[],quantile_costs=[],prices=[],profit_ratios=[])
        for value in (-1,NaN,Inf,-Inf,"bad",1+im)
            @test_throws ArgumentError compare_metrics(uniform; mean_cost=value)
            @test_throws ArgumentError compare_metrics(uniform;
                quantiles=[.5],quantile_costs=[value])
        end
        for value in (-.1,1.1,5,NaN,Inf,-Inf,"bad",1+im)
            @test_throws ArgumentError compare_metrics(uniform;
                quantiles=[value],quantile_costs=[2])
        end
        for value in (NaN,Inf,-Inf,"bad",1+im)
            @test_throws ArgumentError compare_metrics(uniform;
                prices=[value],profit_ratios=[.5])
        end
        for value in (-.1,1.1,35,NaN,Inf,-Inf,"bad",1+im)
            @test_throws ArgumentError compare_metrics(uniform;
                prices=[2],profit_ratios=[value])
        end
        for value in (-1,100.1,NaN,Inf,-Inf)
            @test_throws ArgumentError compare_metrics(uniform;
                prices=[2],profit_ratios=[value],profit_unit=:percent)
        end
        for unit in (:weights,:automatic,"percent",nothing,1)
            @test_throws ArgumentError compare_metrics(uniform; mean_cost=2,profit_unit=unit)
        end
        for kwargs in ((;quantiles=[.5]),(;quantile_costs=[2]),
                       (;prices=[2]),(;profit_ratios=[.5]),
                       (;quantiles=[.1,.9],quantile_costs=[1]),
                       (;prices=[1,2],profit_ratios=[0]))
            @test_throws ArgumentError compare_metrics(uniform; kwargs...)
        end
        @test_throws ArgumentError compare_metrics(uniform;
            quantiles=[.9,.1],quantile_costs=[1,2])
        @test_throws ArgumentError compare_metrics(uniform;
            quantiles=[.5,.5],quantile_costs=[2,2.1])
        for field in (:quantiles,:quantile_costs,:prices,:profit_ratios)
            @test_throws ArgumentError compare_metrics(uniform;
                mean_cost=2,NamedTuple{(field,)}((nothing,))...)
        end
        tiny, huge = big"1e-400",big"1e400"
        for value in (tiny,huge)
            @test_throws ArgumentError compare_metrics(uniform; mean_cost=value)
            @test_throws ArgumentError compare_metrics(uniform;
                quantiles=[.5],quantile_costs=[value])
            @test_throws ArgumentError compare_metrics(uniform;
                quantiles=[value],quantile_costs=[2])
            @test_throws ArgumentError compare_metrics(uniform;
                prices=[value],profit_ratios=[.5])
            @test_throws ArgumentError compare_metrics(uniform;
                prices=[2],profit_ratios=[value])
        end
        @test_throws ArgumentError compare_metrics(uniform;
            prices=[2],profit_ratios=[nextfloat(0.0)],profit_unit=:percent)
        @test compare_metrics(uniform;
            prices=[2],profit_ratios=[nextfloat(0.0)]).profit_references == [nextfloat(0.0)]
        @test_throws ArgumentError compare_metrics(uniform;
            prices=[2],profit_ratios=[floatmax(Float64)],profit_unit=:percent)
    end
end
