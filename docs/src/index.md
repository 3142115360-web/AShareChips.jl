# AShareCostDistributions.jl

AShareCostDistributions.jl is a reproducible research model for estimating holding-cost distributions in Chinese A-share securities. It is a statistical estimate from daily market data, not a reconstruction of account-level positions or a proprietary-terminal clone. Version `0.1.0` uses only the `Dates` standard library at runtime.

```jldoctest
julia> using AShareCostDistributions

julia> grid = PriceGrid([8, 10, 12]);

julia> bars = [DailyBar(low=9, high=9, close=9, turnover=0),
              DailyBar(low=11, high=11, close=11, turnover=0.25)];

julia> chips = chip_distribution(bars; grid);

julia> probabilities(chips) == [0.75, 0.25]
true

julia> average_cost(chips)
9.5

julia> profit_ratio(chips, 10)
0.75
```

Read the [model](model.md) and [data/corporate-action assumptions](assumptions.md) before using market data. With no initial distribution, the first day seeds the model; the zero-turnover first bar in this example still initializes that state.

Build the complete documentation from the package root:

```sh
julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=docs docs/make.jl
python3 -m http.server --bind 127.0.0.1 --directory docs/build 8000
```

Then open `http://127.0.0.1:8000` locally. Continuous integration builds the site and deploys the development version from `main`.

For dated series, file input, and per-day result tables see [importing daily data](data.md). For grid sensitivity and comparison against other sources see [validation and comparisons](validation.md).
