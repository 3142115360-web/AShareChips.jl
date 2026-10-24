using AShareCostDistributions

# A reproducible synthetic workload; no real securities or trading claims.
function runbenchmarks(; days=1000, trials=5)
    grid = PriceGrid(collect(8.0:0.01:14.0))
    bars = [DailyBar(low=9+0.1sin(t), high=12+0.1sin(t),
                     close=10.5+0.1sin(t), turnover=0.03) for t in 1:days]
    for (name, model) in (("uniform",UniformModel()),("triangular",TriangularModel()))
        for (output, compute) in (("final",chip_distribution),("history",chip_history))
            compute(bars;grid,model) # Compile the same specialization before measuring.
            samples = [@timed compute(bars;grid,model) for _ in 1:trials]
            best = samples[argmin([s.time for s in samples])]
            println("julia=",VERSION," days=",days," bins=600 model=",name,
                    " output=",output," trials=",trials," best_seconds=",best.time,
                    " allocated_bytes=",best.bytes," gc_seconds=",best.gctime)
        end
    end
end

runbenchmarks()
