# Performance

The repository includes a reproducible synthetic workload. It measures runtime and allocations, not investment performance, and does not represent every data scale.

```sh
julia --startup-file=no --project=. benchmarks/runbenchmarks.jl
```

The script compiles each call first, then runs it five times and reports the fastest elapsed time, allocated bytes, and garbage-collection time. Its synthetic input contains 1,000 daily observations and 600 price bins. It exercises uniform and triangular daily models for both a final distribution and full history. Data generation, compilation, and downloads are outside the measured region; garbage collection during a run remains included.

The implementation avoids boxed captured variables in the triangular density calculation and does not construct per-day model or adjustment lists for default inputs. It reuses ordinary input vectors without modifying them. Historical snapshots remain independent objects.

Version 0.1 still allocates probability and state arrays for daily updates. It makes no zero-allocation, GPU, arbitrary-precision, or multi-security batch-performance commitment. Benchmark results depend on Julia version, hardware, concurrent load, and garbage-collector state, so record that environment with any reported number.
