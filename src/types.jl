# Float64 is the deliberate numerical contract for v0.1.
function _finite(x::Real, name::AbstractString)
    y = Float64(x)
    isfinite(y) || throw(ArgumentError("$name must be finite and representable as Float64"))
    !iszero(x) && iszero(y) && throw(ArgumentError("$name is nonzero but underflows Float64"))
    return y
end

"""
    PriceGrid(edges)

Histogram bin boundaries, finite, nonnegative and strictly increasing. At least
one bin is required. Input is copied; treat stored fields as read-only.
Nonzero inputs that underflow conversion to Float64 are rejected.
"""
struct PriceGrid
    edges::Vector{Float64}
    function PriceGrid(edges::AbstractVector{<:Real})
        e = [_finite(x, "edge") for x in edges]
        length(e) >= 2 || throw(ArgumentError("at least two edges are required"))
        e[1] >= 0 || throw(ArgumentError("price edges must be nonnegative"))
        all(i -> e[i+1] > e[i] && isfinite(e[i+1] - e[i]), 1:length(e)-1) ||
            throw(ArgumentError("edges must be strictly increasing with finite widths"))
        new(e)
    end
end

function _normalized(weights::AbstractVector{<:Real})
    m = [_finite(x, "mass") for x in weights]
    isempty(m) && throw(ArgumentError("mass must not be empty"))
    all(x -> x >= 0, m) || throw(ArgumentError("mass must be nonnegative"))
    scale = maximum(m)
    scale > 0 || throw(ArgumentError("total mass must be positive"))
    for i in eachindex(m)
        before = m[i]
        m[i] /= scale
        before > 0 && m[i] == 0 && throw(ArgumentError("positive mass underflows during scaling"))
    end
    total = sum(m)
    for i in eachindex(m)
        before = m[i]
        m[i] /= total
        before > 0 && m[i] == 0 && throw(ArgumentError("positive mass underflows during normalization"))
    end
    return m
end

"""
    ChipDistribution(grid, mass)

A normalized cost histogram. Each bin's probability is spread uniformly within
its boundaries, including bins populated by point trades. Mass is copied and
normalized; treat stored fields as read-only. Accessors return independent copies.
Normalization rejects positive weights whose ratios underflow to zero.
"""
struct ChipDistribution
    grid::PriceGrid
    mass::Vector{Float64}
    function ChipDistribution(grid::PriceGrid, mass::AbstractVector{<:Real})
        length(mass) == length(grid.edges)-1 || throw(ArgumentError("mass/grid size mismatch"))
        new(grid, _normalized(mass))
    end
end

"Return a copy of the histogram boundaries."
bin_edges(d::ChipDistribution) = copy(d.grid.edges)
bin_edges(g::PriceGrid) = copy(g.edges)
"Return the midpoint representative price of every bin."
price_centers(g::PriceGrid) = [g.edges[i] + (g.edges[i+1]-g.edges[i])/2 for i in 1:length(g.edges)-1]
price_centers(d::ChipDistribution) = price_centers(d.grid)
"Return a copy of normalized bin probabilities."
probabilities(d::ChipDistribution) = copy(d.mass)

# Rare tiny-mass comparisons need an exact representation to retain contributions
# buried below a large cumulative sum. This does not change the public Float64 API.
_needs_exact_mass(d::ChipDistribution) = any(w -> 0 < w < eps(Float64),d.mass)
_rational(x::Float64) = Rational{BigInt}(x)

function _rational_cost_quantile(d::ChipDistribution, q::Float64)
    mass = _rational.(d.mass)
    q == 0 && return _rational(d.grid.edges[findfirst(>(0),d.mass)])
    q == 1 && return _rational(d.grid.edges[findlast(>(0),d.mass)+1])
    target = _rational(q)*sum(mass)
    cumulative = zero(Rational{BigInt})
    for i in eachindex(mass)
        w = mass[i]
        w == 0 && continue
        following = cumulative+w
        if target <= following
            left, right = _rational(d.grid.edges[i]), _rational(d.grid.edges[i+1])
            return left+(target-cumulative)/w*(right-left)
        end
        cumulative = following
    end
    return _rational(d.grid.edges[findlast(>(0),d.mass)+1])
end

"""
    DailyBar(; low, high, close, turnover, vwap=nothing)

One chronological observation. Prices must be positive, finite, in the same price
basis, and low ≤ close ≤ high. Optional VWAP is supplied by the caller and must
lie in the trading range. Turnover is a nonnegative fraction (0.05 = 5%), not a
percent; values above 1 are allowed. No volume/free-float inference is performed.
"""
struct DailyBar
    low::Float64
    high::Float64
    close::Float64
    turnover::Float64
    vwap::Union{Nothing,Float64}
    function DailyBar(; low::Real, high::Real, close::Real, turnover::Real,
                      vwap::Union{Nothing,Real}=nothing)
        l, h, c, t = _finite(low,"low"), _finite(high,"high"),
                     _finite(close,"close"), _finite(turnover,"turnover")
        0 < l <= c <= h || throw(ArgumentError("require 0 < low ≤ close ≤ high"))
        t >= 0 || throw(ArgumentError("turnover must be nonnegative"))
        v = isnothing(vwap) ? nothing : _finite(vwap,"vwap")
        (isnothing(v) || l <= v <= h) || throw(ArgumentError("vwap must be within [low, high]"))
        new(l,h,c,t,v)
    end
end

"""
    PriceAdjustment(; scale=1, shift=0)

Explicit cost-coordinate transform p_new = scale * p_old + shift, applied before
that day's turnover update. Scale must be positive. This is a modeling transform,
not an automatic interpretation of dividends, rights issues or free-float changes.
"""
struct PriceAdjustment
    scale::Float64
    shift::Float64
    function PriceAdjustment(; scale::Real=1, shift::Real=0)
        s, b = _finite(scale,"scale"), _finite(shift,"shift")
        s > 0 || throw(ArgumentError("scale must be positive"))
        new(s,b)
    end
end
