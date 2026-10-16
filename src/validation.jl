function _comparison_values(values, name::AbstractString; unit_interval::Bool=false)
    result = Float64[]
    for value in values
        value isa Real || throw(ArgumentError("$name values must be real numbers"))
        x = _finite(value, name)
        (!unit_interval || 0 <= x <= 1) ||
            throw(ArgumentError("quantiles must be in [0,1]"))
        push!(result, x)
    end
    return result
end

# Points must be sorted. Evaluate by integrating each histogram's own bins,
# without resampling either distribution onto the other grid.
function _histogram_cdfs(d::ChipDistribution, points::Vector{Float64})
    edges, mass = d.grid.edges, d.mass
    values = zeros(length(points))
    bin, cumulative = 1, 0.0
    for (i, price) in pairs(points)
        if price <= edges[1]
            values[i] = 0.0
        elseif price >= edges[end]
            values[i] = 1.0
        else
            while edges[bin+1] <= price
                cumulative += mass[bin]
                bin += 1
            end
            fraction = (price-edges[bin])/(edges[bin+1]-edges[bin])
            values[i] = clamp(cumulative + mass[bin]*fraction, 0.0, 1.0)
        end
    end
    return values
end

function _histogram_survivals(d::ChipDistribution, points::Vector{Float64})
    edges, mass = d.grid.edges, d.mass
    values = zeros(length(points))
    bin, tail = length(mass), 0.0
    for i in length(points):-1:1
        price = points[i]
        if price >= edges[end]
            values[i] = 0.0
        elseif price <= edges[1]
            values[i] = 1.0
        else
            while edges[bin] > price
                tail += mass[bin]
                bin -= 1
            end
            fraction = (edges[bin+1]-price)/(edges[bin+1]-edges[bin])
            values[i] = clamp(tail+mass[bin]*fraction,0.0,1.0)
        end
    end
    return values
end

function _cdf_differences(estimate::ChipDistribution, reference::ChipDistribution, points::Vector{Float64})
    left_est, left_ref = _histogram_cdfs(estimate,points), _histogram_cdfs(reference,points)
    right_est, right_ref = _histogram_survivals(estimate,points), _histogram_survivals(reference,points)
    return [left_est[i]+left_ref[i] <= 1 ? left_est[i]-left_ref[i] : right_ref[i]-right_est[i]
            for i in eachindex(points)]
end

function _rational_cdfs(d::ChipDistribution, points::Vector{Float64})
    edges, mass = _rational.(d.grid.edges), _rational.(d.mass)
    total = sum(mass)
    result = Vector{Rational{BigInt}}(undef,length(points))
    bin, cumulative = 1, zero(Rational{BigInt})
    for i in eachindex(points)
        price = _rational(points[i])
        if price <= edges[1]
            result[i] = 0
        elseif price >= edges[end]
            result[i] = 1
        else
            while edges[bin+1] <= price
                cumulative += mass[bin]
                bin += 1
            end
            result[i] = (cumulative+mass[bin]*(price-edges[bin])/(edges[bin+1]-edges[bin]))/total
        end
    end
    return result
end

function _rational_comparison(estimate,reference,points,qvec,pvec)
    difference = _rational_cdfs(estimate,points) .- _rational_cdfs(reference,points)
    distance, signed = zero(Rational{BigInt}), zero(Rational{BigInt})
    for i in 1:length(points)-1
        width = _rational(points[i+1])-_rational(points[i])
        left, right = difference[i], difference[i+1]
        signed += width*(left+right)/2
        if (left < 0 < right) || (right < 0 < left)
            distance += width*(left^2+right^2)/(2*(abs(left)+abs(right)))
        else
            distance += width*(abs(left)+abs(right))/2
        end
    end
    profit = _rational_cdfs(estimate,sort!(unique(copy(pvec)))) .-
             _rational_cdfs(reference,sort!(unique(copy(pvec))))
    lookup = Dict(zip(sort!(unique(copy(pvec))),profit))
    return (max_cdf_error=Float64(maximum(abs,difference)),wasserstein1=Float64(distance),
            mean_cost_error=Float64(-signed),quantiles=qvec,
            quantile_errors=[Float64(_rational_cost_quantile(estimate,q)-_rational_cost_quantile(reference,q)) for q in qvec],
            prices=pvec,profit_errors=[Float64(lookup[p]) for p in pvec],comparison_points=points)
end

function _signed_linear_area(width::Float64, left::Float64, right::Float64)
    scale = max(abs(left),abs(right))
    scale == 0 && return 0.0
    return (width*scale)*(left/scale/2+right/scale/2)
end

function _absolute_linear_area(width::Float64, left::Float64, right::Float64)
    a, b = abs(left), abs(right)
    scale = max(a,b)
    scale == 0 && return 0.0
    a, b = a/scale, b/scale
    if (left < 0 < right) || (right < 0 < left)
        # The zero divides the segment into two triangles. Working with
        # scaled ratios avoids premature underflow for tiny CDF differences.
        ratio = a/(a+b)
        return (width*scale)*((a/2)*ratio + (b/2)*(1-ratio))
    end
    return (width*scale)*(a/2+b/2)
end

"""
    compare_distributions(estimate, reference; quantiles=[0.1, 0.5, 0.9], prices=nothing)

Compare two cost histograms without requiring identical grids. Returns a named
tuple with `max_cdf_error`, `wasserstein1`, signed `mean_cost_error`, copied
`quantiles` and signed `quantile_errors`, copied `prices` and signed
`profit_errors`, and `comparison_points` (the sorted union of both grids' edges).
All signed errors are estimate minus reference. Default prices are the reference
bin midpoints; user-supplied prices retain their order, as do quantiles. Repeated
points and empty quantile/price lists are allowed. Quantiles must be finite in
[0,1]; prices must be finite.

The maximum absolute CDF difference is evaluated at every union edge, which is
exact for the represented piecewise-uniform histograms up to Float64 rounding.
`wasserstein1` integrates the absolute linear CDF difference on every segment,
splitting sign crossings; it and cost errors use price units. CDF/profit errors
use fractional probability units. Neither input is changed. Numerical agreement
does not establish real account holdings or a proprietary algorithm's internals.
The mean difference is integrated from the CDF difference to avoid subtracting
two rounded large means. Tiny positive masses below machine epsilon trigger
an exact-rational normalization/integration fallback; outputs remain Float64.
"""
function compare_distributions(estimate::ChipDistribution, reference::ChipDistribution;
                               quantiles=[0.1, 0.5, 0.9], prices=nothing)
    qvec = _comparison_values(quantiles, "quantile"; unit_interval=true)
    pvec = isnothing(prices) ? price_centers(reference) :
           _comparison_values(prices, "price")
    points = sort!(unique(vcat(estimate.grid.edges, reference.grid.edges)))
    if _needs_exact_mass(estimate) || _needs_exact_mass(reference)
        return _rational_comparison(estimate,reference,points,qvec,pvec)
    end
    differences = _cdf_differences(estimate,reference,points)
    distance = sum(_absolute_linear_area(points[i+1]-points[i],differences[i],differences[i+1])
                   for i in 1:length(points)-1)
    mean_error = -sum(_signed_linear_area(points[i+1]-points[i],differences[i],differences[i+1])
                      for i in 1:length(points)-1)
    # Evaluate differences directly, retaining tiny tails even when both CDFs round to one.
    sorted_prices = sort!(unique(copy(pvec)))
    profit_at_price = Dict(zip(sorted_prices,_cdf_differences(estimate,reference,sorted_prices)))
    return (max_cdf_error=maximum(abs, differences), wasserstein1=distance,
            mean_cost_error=mean_error,
            quantiles=qvec,
            quantile_errors=[cost_quantile(estimate,q)-cost_quantile(reference,q) for q in qvec],
            prices=pvec,
            profit_errors=[profit_at_price[p] for p in pvec],
            comparison_points=points)
end

"""
    grid_convergence(bars, grids; reference_grid=nothing,
                     quantiles=[0.1, 0.5, 0.9], prices=nothing, initial=nothing, kwargs...)

Run `chip_distribution` on each `PriceGrid` in `grids`, then compare each final
histogram with the result on `reference_grid` (the last supplied grid by default).
Returns one named tuple per input grid in input order, with `bin_count`,
`max_bin_width`, and the fields of `compare_distributions`. A supplied reference
whose edges match an input grid reuses that run; its comparison is exactly zero.
An external reference grid requires one additional simulation.

The grid vector must be nonempty. Non-`nothing` initial states are rejected:
silently changing their histogram across grids would confound this experiment.
Other simulation keywords are forwarded, including model and adjustments. Every
grid must cover the daily ranges and the full positive-mass transformed support;
normal simulation validation applies. A `BarSeries` retains its basis validation;
other observation iterators and adjustment iterators are collected once for
repeatable runs. This measures discrepancies against a
chosen histogram, and does not claim that the finest grid is ground truth or that
arbitrary sequences of grids converge monotonically.
"""
function grid_convergence(bars, grids::AbstractVector{PriceGrid};
                          reference_grid::Union{Nothing,PriceGrid}=nothing,
                          quantiles=[0.1, 0.5, 0.9], prices=nothing,
                          initial::Union{Nothing,ChipDistribution}=nothing, kwargs...)
    isempty(grids) && throw(ArgumentError("at least one grid is required"))
    isnothing(initial) || throw(ArgumentError("grid_convergence does not accept an initial distribution"))
    haskey(kwargs, :grid) && throw(ArgumentError("provide simulation grids positionally, not with grid"))
    qvec = _comparison_values(quantiles, "quantile"; unit_interval=true)
    pvec = isnothing(prices) ? nothing : _comparison_values(prices, "price")
    observations = bars isa BarSeries ? bars : collect(bars)
    options = (; kwargs...)
    if haskey(options, :adjustments) && !isnothing(options.adjustments)
        options = merge(options, (adjustments=collect(options.adjustments),))
    end
    results = [chip_distribution(observations; grid, options...) for grid in grids]
    target = isnothing(reference_grid) ? last(grids) : reference_grid
    reference_index = findlast(grid -> _samegrid(grid, target), grids)
    reference = isnothing(reference_index) ?
        chip_distribution(observations; grid=target, options...) : results[reference_index]
    return [merge((bin_count=length(grid.edges)-1,
                   max_bin_width=maximum(diff(grid.edges))),
                  compare_distributions(result, reference; quantiles=qvec, prices=pvec))
            for (grid, result) in zip(grids, results)]
end
