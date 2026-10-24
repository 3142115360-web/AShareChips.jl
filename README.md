# AShareCostDistributions.jl

[![CI](https://github.com/3142115360-web/AShareCostDistributions.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/3142115360-web/AShareCostDistributions.jl/actions/workflows/CI.yml)
[![Documentation](https://github.com/3142115360-web/AShareCostDistributions.jl/actions/workflows/Docs.yml/badge.svg)](https://3142115360-web.github.io/AShareCostDistributions.jl/)
[![Line coverage](https://3142115360-web.github.io/AShareCostDistributions.jl/coverage/coverage.svg)](https://3142115360-web.github.io/AShareCostDistributions.jl/coverage/)

`AShareCostDistributions.jl` is a Julia research package for estimating the cost distribution of holdings in Chinese A-share securities from daily market data. It is a statistical model: it does **not** reconstruct account-level positions or claim parity with proprietary charting terminals.

The package models the estimated holding costs often called 筹码分布 in Chinese technical analysis. It provides modelling and validation tools rather than trading signals.

## Installation

After the General registration is merged, install the release with Julia's package manager:

```julia
using Pkg
Pkg.add("AShareCostDistributions")
```

To test the current development branch instead:

```julia
using Pkg
Pkg.add(url="https://github.com/3142115360-web/AShareCostDistributions.jl", rev="main")
using AShareCostDistributions
```

The package supports Julia 1.10 and later. Runtime code depends only on the Julia standard library (`Dates`). Continuous integration exercises Linux, macOS, and Windows; the published documentation is built from the same source.

## What it provides

- Histogram cost distributions on an explicit `PriceGrid`.
- Uniform, triangular, and empirical daily-trading cost models.
- Linear and exponential effective-turnover replacement models.
- Mean cost, profitable-holder ratio, cost quantiles, and concentration intervals.
- Explicit price-basis and corporate-action metadata, including affine rebasing.
- Strict import of simple daily-bar, reference-distribution, adjustment-event, and metric-summary files.
- Distribution/history comparison tools and synthetic reference fixtures.

The main recurrence is `C_t(p) = (1 - α_t) C_(t-1)(p) + α_t D_t(p)`, where `D_t` is an estimated distribution of that day's trades and `α_t` is a configurable effective turnover. See the [documentation site](https://3142115360-web.github.io/AShareCostDistributions.jl/) for assumptions, data contracts, and API details.

## Quick example

```julia
using AShareCostDistributions

grid = PriceGrid(collect(8.0:0.02:14.0))
bars = [
    DailyBar(low=9.0, high=10.0, close=9.5, turnover=0.0),
    DailyBar(low=10.0, high=11.0, close=10.5, turnover=0.25),
]
chips = chip_distribution(bars; grid)

average_cost(chips)
profit_ratio(chips, 10.5)       # a fraction, not a percentage
cost_quantile(chips, 0.5)
concentration(chips; coverage=0.9)
```

For realistic data, explicitly declare the price basis and turnover denominator before constructing a `BarSeries`. The package rejects ambiguous or internally inconsistent inputs instead of guessing.

## Validation and limitations

The repository contains analytical and regression tests, cross-grid comparison utilities, and a reproducible comparison with one public-market model. That comparison found measurable differences; it is not a validation against Tongdaxin or any other proprietary terminal. Corporate-action handling requires a verified adjustment-event source, and real-market results remain estimates.

## Chinese overview

[中文说明](README.zh.md) summarizes the package in Chinese. The English README and documentation site are the primary public entry points so that users of the General registry can evaluate the package.

## Contributing and license

Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening an issue or pull request. The package is released under the [MIT License](LICENSE).

Maintainer: **Zhao.Ruihong (赵芮弘)**. The implementation, tests, and documentation include substantial assistance from OpenAI Codex. The maintainer has confirmed review of the code and responsibility for ongoing maintenance. Contributors remain responsible for reviewing and understanding changes before release.
