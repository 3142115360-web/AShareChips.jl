_samegrid(a::PriceGrid,b::PriceGrid) = a.edges == b.edges
_identity(a::PriceAdjustment) = a.scale == 1 && a.shift == 0

function _alpha(alpha::Real)
    a = _finite(alpha,"alpha")
    0 <= a <= 1 || throw(ArgumentError("alpha must be in [0,1]"))
    return a
end

"""
    update_chips(previous, daily, alpha)

Return (1-alpha)*previous + alpha*daily on identical grids. Alpha must be finite
in [0,1]. Historical holders are assumed to exit proportionally at every cost.
Neither input is mutated.
"""
function update_chips(previous::ChipDistribution, daily::ChipDistribution, alpha::Real)
    a = _alpha(alpha)
    _samegrid(previous.grid,daily.grid) || throw(ArgumentError("distributions must share bin edges"))
    result = (1-a).*previous.mass .+ a.*daily.mass
    for i in eachindex(result)
        expected_positive = (a < 1 && previous.mass[i] > 0) || (a > 0 && daily.mass[i] > 0)
        expected_positive && result[i] == 0 && throw(ArgumentError("positive updated mass underflows Float64"))
    end
    return ChipDistribution(previous.grid,result)
end

"""
    rebase(distribution, adjustment; grid=distribution.grid)

Apply an affine cost-coordinate transform, then conservatively distribute each
transformed source bin's uniform mass over overlapping target bins. The target
must cover every positive-mass transformed bin in full. Negative transformed
support, floating-point bin collapse and clipping raise ArgumentError.
"""
function rebase(d::ChipDistribution, a::PriceAdjustment; grid::PriceGrid=d.grid)
    result = zeros(length(grid.edges)-1)
    j = 1
    for i in eachindex(d.mass)
        w = d.mass[i]
        w == 0 && continue
        lo = fma(a.scale,d.grid.edges[i],a.shift)
        hi = fma(a.scale,d.grid.edges[i+1],a.shift)
        (isfinite(lo) && isfinite(hi) && 0 <= lo < hi && isfinite(hi-lo)) ||
            throw(ArgumentError("transformed support must be finite, nonnegative and nondegenerate"))
        _covered(grid,lo,hi)
        while j < length(result) && grid.edges[j+1] <= lo
            j += 1
        end
        k = j
        while k <= length(result) && grid.edges[k] < hi
            overlap = min(hi,grid.edges[k+1])-max(lo,grid.edges[k])
            if overlap > 0
                contribution = w*(overlap/(hi-lo))
                contribution > 0 || throw(ArgumentError("positive rebinned mass underflows Float64"))
                result[k] += contribution
            end
            k += 1
        end
    end
    return ChipDistribution(grid,result)
end

function _simulate(bars; grid::PriceGrid, model=TriangularModel(),
                   turnover_model::AbstractTurnoverModel=LinearTurnover(),
                   initial::Union{Nothing,ChipDistribution}=nothing,
                   adjustments=nothing, keep_history::Bool)
    observations = bars isa Vector ? bars : collect(bars)
    n = length(observations)
    n > 0 || throw(ArgumentError("at least one bar is required"))
    all(b -> b isa DailyBar,observations) || throw(ArgumentError("bars must contain DailyBar values"))
    models = if model isa AbstractDailyModel
        model
    elseif model isa AbstractVector && length(model) == n && all(m -> m isa AbstractDailyModel,model)
        model
    else
        throw(ArgumentError("model must be a daily model or one model per observation"))
    end
    changes = isnothing(adjustments) ? nothing :
        (adjustments isa Vector ? adjustments : collect(adjustments))
    if !isnothing(changes)
        (length(changes) == n && all(a -> a isa PriceAdjustment,changes)) ||
            throw(ArgumentError("provide one PriceAdjustment per observation"))
    end
    if !isnothing(initial)
        _samegrid(initial.grid,grid) || throw(ArgumentError("initial state must use the simulation grid"))
    elseif !isnothing(changes) && !_identity(changes[1])
        throw(ArgumentError("the first adjustment requires an explicit initial state"))
    end
    state = initial
    history = ChipDistribution[]
    keep_history && sizehint!(history,n)
    for t in 1:n
        daymodel = models isa AbstractDailyModel ? models : models[t]
        daily = daily_distribution(daymodel,grid,observations[t])
        _samegrid(daily.grid,grid) || throw(ArgumentError("daily model returned a different grid"))
        alpha = _alpha(effective_turnover(turnover_model,observations[t].turnover))
        if isnothing(state)
            # A seed is necessary even when the first observation has zero turnover.
            state = daily
        else
            prior = isnothing(changes) || _identity(changes[t]) ? state : rebase(state,changes[t];grid)
            state = update_chips(prior,daily,alpha)
        end
        keep_history && push!(history,state)
    end
    return keep_history ? history : state
end

"""
    chip_history(bars; grid, model=TriangularModel(),
                 turnover_model=LinearTurnover(), initial=nothing, adjustments=nothing)

Chronological snapshots after each bar. Without a prior, the first day's full
cost distribution seeds the state (its turnover does not control that seed).
With a prior, every day uses the recurrence. Adjustments apply to the previous
state before replacement; today's prices are already in the new basis. An
initial state is required for a nonidentity first-day adjustment. Models may be
one shared model or a vector of per-day models. Dates/order are caller-owned.
"""
chip_history(bars; kwargs...) = _simulate(bars;kwargs...,keep_history=true)

"""
    chip_distribution(bars; grid, kwargs...)

Final histogram, with the same assumptions and keywords as `chip_history`.
Only the final state is retained; history storage is not allocated. Empty input
raises ArgumentError. Numerical state storage is O(number of bins), in addition
to the collected input observations and models.
"""
chip_distribution(bars;kwargs...) = _simulate(bars;kwargs...,keep_history=false)
