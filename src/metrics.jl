"Return the histogram mean cost, sum(mass * bin midpoint), in price units."
average_cost(d::ChipDistribution) = sum(d.mass .* price_centers(d))

"""
    profit_ratio(distribution, price)

Histogram probability of cost below the supplied finite price. Integrates the
uniform density within a bin; returns a fraction in [0,1]. Equality has zero mass
under this histogram contract. This estimate is not observed account profitability.
"""
function profit_ratio(d::ChipDistribution, price::Real)
    p = _finite(price,"price")
    e = d.grid.edges
    p <= e[1] && return 0.0
    p >= e[end] && return 1.0
    i = searchsortedlast(e,p)
    left = sum(@view d.mass[1:i-1])
    return clamp(left + d.mass[i]*((p-e[i])/(e[i+1]-e[i])),0.0,1.0)
end

"""
    cost_quantile(distribution, q)

Inverse histogram CDF, with linear interpolation within positive-mass bins.
q ∈ [0,1]; endpoints return the positive-mass support boundaries. At a flat CDF
plateau, the inverse returns the leftmost price achieving q.
For tiny masses below machine epsilon, internal exact-rational normalization
avoids losing a quantile crossing through cumulative rounding.
"""
function cost_quantile(d::ChipDistribution, q::Real)
    x = _finite(q,"quantile")
    0 <= x <= 1 || throw(ArgumentError("quantile must be in [0,1]"))
    _needs_exact_mass(d) && return Float64(_rational_cost_quantile(d,x))
    firstbin = findfirst(>(0),d.mass)
    lastbin = findlast(>(0),d.mass)
    x == 0 && return d.grid.edges[firstbin]
    x == 1 && return d.grid.edges[lastbin+1]
    cumulative = 0.0
    for i in eachindex(d.mass)
        w = d.mass[i]
        w == 0 && continue
        following = cumulative + w
        if x <= following
            fraction = clamp((x-cumulative)/w,0.0,1.0)
            return d.grid.edges[i] + fraction*(d.grid.edges[i+1]-d.grid.edges[i])
        end
        cumulative = following
    end
    # Account for a normalized sum rounding slightly below one.
    return d.grid.edges[lastbin+1]
end

"""
    concentration(distribution; coverage=0.9)

Equal-tail cost interval Q((1-coverage)/2) to Q((1+coverage)/2). Returns
(lower, upper, width, relative_width), with relative_width = width/(upper+lower)
computed stably. Both widths grow as chips become more dispersed. This is not a
shortest-density interval and is not a verified proprietary software definition.
Raises ArgumentError if subnormal price rounding produces a zero denominator.
"""
function concentration(d::ChipDistribution; coverage::Real=0.9)
    c = _finite(coverage,"coverage")
    0 < c <= 1 || throw(ArgumentError("coverage must be in (0,1]"))
    lo = cost_quantile(d,(1-c)/2)
    hi = cost_quantile(d,(1+c)/2)
    hi > 0 || throw(ArgumentError("price grid is too small to represent concentration reliably"))
    width = hi-lo
    relative_width = (width/hi)/(1+lo/hi)
    return (lower=lo,upper=hi,width=width,relative_width=relative_width)
end
