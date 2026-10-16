"Extension point: implement `daily_distribution(model, grid, bar)` returning a ChipDistribution."
abstract type AbstractDailyModel end
"Uniform trading cost density on [low, high]."
struct UniformModel <: AbstractDailyModel end

"""
    TriangularModel(; peak=:typical)

Triangular density on [low, high]. `:typical` uses (low+high+close)/3,
`:close` uses close, and `:vwap` requires caller-supplied VWAP. A typical price
is a proxy, not a VWAP computed from daily OHLC.
"""
struct TriangularModel <: AbstractDailyModel
    peak::Symbol
    function TriangularModel(; peak::Symbol=:typical)
        peak in (:typical,:close,:vwap) || throw(ArgumentError("unknown triangular peak"))
        new(peak)
    end
end

"""
    EmpiricalModel(prices, volumes)

Volume-weighted trades for one observation. Inputs are copied. Volumes must be
finite, nonnegative and have a positive total. Prices must be positive and within
the bar's range when evaluated. Use a vector of models for multi-day trade data.
"""
struct EmpiricalModel <: AbstractDailyModel
    prices::Vector{Float64}
    weights::Vector{Float64}
    function EmpiricalModel(prices::AbstractVector{<:Real}, volumes::AbstractVector{<:Real})
        length(prices) == length(volumes) || throw(ArgumentError("prices/volumes size mismatch"))
        p = [_finite(x,"trade price") for x in prices]
        all(x -> x > 0, p) || throw(ArgumentError("trade prices must be positive"))
        new(p, _normalized(volumes))
    end
end

"Extension point: implement `effective_turnover(model, tau)` returning a value in [0,1]."
abstract type AbstractTurnoverModel end
"Linear replacement fraction clamp(k * tau, 0, 1), with finite nonnegative k."
struct LinearTurnover <: AbstractTurnoverModel
    k::Float64
    function LinearTurnover(; k::Real=1)
        x = _finite(k,"k")
        x >= 0 || throw(ArgumentError("k must be nonnegative"))
        new(x)
    end
end
"Exponential replacement fraction 1-exp(-k*tau), with finite nonnegative k."
struct ExponentialTurnover <: AbstractTurnoverModel
    k::Float64
    function ExponentialTurnover(; k::Real=1)
        x = _finite(k,"k")
        x >= 0 || throw(ArgumentError("k must be nonnegative"))
        new(x)
    end
end

function _turnover(tau::Real)
    x = _finite(tau,"turnover")
    x >= 0 || throw(ArgumentError("turnover must be nonnegative"))
    return x
end

"Compute the effective fraction of old chips replaced; tau uses fractional units."
function effective_turnover(m::LinearTurnover, tau::Real)
    value = _scaled_turnover(m.k,tau)
    return clamp(value,0.0,1.0)
end
effective_turnover(m::ExponentialTurnover, tau::Real) = -expm1(-_scaled_turnover(m.k,tau))

function _scaled_turnover(k::Float64, tau::Real)
    t = _turnover(tau)
    value = k*t
    k > 0 && t > 0 && value == 0 && throw(ArgumentError("positive effective turnover underflows Float64"))
    return value
end

function _covered(grid::PriceGrid, l::Float64, h::Float64)
    grid.edges[1] <= l <= h <= grid.edges[end] ||
        throw(ArgumentError("grid must cover the full trading range; clipping is not allowed"))
end

function _bin(grid::PriceGrid, p::Float64)
    _covered(grid,p,p)
    return min(searchsortedlast(grid.edges,p),length(grid.edges)-1)
end

function _point_distribution(grid::PriceGrid, p::Float64)
    m = zeros(length(grid.edges)-1)
    m[_bin(grid,p)] = 1
    return ChipDistribution(grid,m)
end

function _kernel_distribution(integral, grid::PriceGrid, low::Float64, high::Float64)
    mass = zeros(length(grid.edges)-1)
    for i in eachindex(mass)
        left, right = max(low,grid.edges[i]), min(high,grid.edges[i+1])
        if right > left
            weight = integral(left,right)
            isfinite(weight) && weight > 0 ||
                throw(ArgumentError("positive daily probability is not representable as Float64"))
            mass[i] = weight
        end
    end
    return ChipDistribution(grid,mass)
end

"""
    daily_distribution(model, grid, bar)

Project a day's costs onto the histogram. Continuous kernels integrate local density segments
over bins, avoiding cancellation between nearly equal CDF values. Point prices map to [left,right), with the final edge included;
the histogram subsequently represents their bin uniformly. The full bar range
must be covered, including for empirical models; no tail clipping occurs.
"""
function daily_distribution(::UniformModel, grid::PriceGrid, bar::DailyBar)
    l,h = bar.low,bar.high
    _covered(grid,l,h)
    l == h && return _point_distribution(grid,l)
    integral(left,right) = (right-left)/(h-l)
    return _kernel_distribution(integral,grid,l,h)
end

function daily_distribution(model::TriangularModel, grid::PriceGrid, bar::DailyBar)
    l,h = bar.low,bar.high
    _covered(grid,l,h)
    peak = model.peak == :vwap ?
        (isnothing(bar.vwap) ? throw(ArgumentError(":vwap peak requires vwap")) : bar.vwap::Float64) :
        model.peak == :close ? bar.close : l/3 + h/3 + bar.close/3
    # Prevent a one-ulp excursion of a rounded typical price at a locked limit.
    mode = clamp(peak,l,h)
    l == h && return _point_distribution(grid,l)
    function integral(left,right)
        weight = 0.0
        if mode > l && left < mode
            stop = min(right,mode)
            weight += ((stop-left)/(h-l))*((left-l)/(mode-l)+(stop-l)/(mode-l))
        end
        if mode < h && right > mode
            start = max(left,mode)
            weight += ((right-start)/(h-l))*((h-start)/(h-mode)+(h-right)/(h-mode))
        end
        return weight
    end
    return _kernel_distribution(integral,grid,l,h)
end

function daily_distribution(model::EmpiricalModel, grid::PriceGrid, bar::DailyBar)
    _covered(grid,bar.low,bar.high)
    m = zeros(length(grid.edges)-1)
    for (p,w) in zip(model.prices,model.weights)
        bar.low <= p <= bar.high || throw(ArgumentError("trade price outside the bar range"))
        m[_bin(grid,p)] += w
    end
    return ChipDistribution(grid,m)
end
