# Materialize each supplied iterable once, using the package's Float64 contract.
function _metric_values(values, name; unit_interval=false, nonnegative=false)
    applicable(iterate, values) || throw(ArgumentError("$name must be an iterable of real numbers"))
    result = _comparison_values(values, name; unit_interval)
    (!nonnegative || all(>=(0), result)) ||
        throw(ArgumentError("$name values must be nonnegative"))
    return result
end

function _metric_quantile_order(quantiles, costs)
    order = sortperm(quantiles)
    for i in 2:length(order)
        before, after = order[i-1], order[i]
        if quantiles[before] == quantiles[after]
            costs[before] == costs[after] ||
                throw(ArgumentError("repeated quantiles must have equal reference costs"))
        else
            costs[before] <= costs[after] ||
                throw(ArgumentError("reference costs must be nondecreasing in quantile"))
        end
    end
    return nothing
end

"""
    compare_metrics(estimate::ChipDistribution; mean_cost=nothing,
                    quantiles=[], quantile_costs=[], prices=[], profit_ratios=[],
                    profit_unit=:fraction)

Compare a cost histogram with supplied scalar summaries, without constructing a
reference histogram. At least one mean, quantile or profit summary is required.
All signed errors are estimate minus reference. Mean and quantile costs/errors
use price units; profit values/errors always use fractional probability units.

`mean_cost` is optional, finite and nonnegative. A median such as `COST(50)` must
instead be supplied as a cost at quantile `0.5`; it is not the mean cost.
`quantiles` and `quantile_costs` are equal-length iterables: quantiles are finite
fractions in [0,1], and reference costs are finite and nonnegative. Costs must be
nondecreasing in quantile; repeated quantiles must have equal reference costs.
`prices` and `profit_ratios` also have equal lengths. Evaluation prices must be
finite and can be outside the support. Reference profit inputs are in [0,1] for
`profit_unit=:fraction`, or [0,100] for the explicit `:percent` setting. There is
no unit inference. Nonzero inputs that underflow Float64 conversion, including
positive percent values that underflow division by 100, are rejected.

Return a flat named tuple containing `mean_cost_estimate`, `mean_cost_reference`
and `mean_cost_error` (all `nothing` when absent), `quantiles`,
`quantile_estimates`, `quantile_references`, `quantile_errors`, `prices`,
`profit_estimates`, `profit_references` and `profit_errors`. Input iterables are
consumed once; returned vectors are independent copies and preserve input order.
Repeated prices retain repeated results. No input distribution is changed.

The caller must establish the evaluation price, date, security, price basis,
summary definitions and data provenance before comparing. This function neither
aligns histories nor verifies a provider's units or undisclosed model. Sparse
summaries do not identify a full distribution, so this result contains neither
Wasserstein distance nor a maximum full-CDF error or compatibility verdict.
"""
function compare_metrics(estimate::ChipDistribution; mean_cost=nothing,
                         quantiles=[], quantile_costs=[], prices=[], profit_ratios=[],
                         profit_unit=:fraction)
    profit_unit isa Symbol && profit_unit in (:fraction, :percent) ||
        throw(ArgumentError("profit_unit must be :fraction or :percent"))
    mean_reference = if isnothing(mean_cost)
        nothing
    else
        mean_cost isa Real || throw(ArgumentError("mean_cost must be a real number or nothing"))
        value = _finite(mean_cost, "mean_cost")
        value >= 0 || throw(ArgumentError("mean_cost must be nonnegative"))
        value
    end
    qvec = _metric_values(quantiles, "quantile"; unit_interval=true)
    qref = _metric_values(quantile_costs, "reference quantile cost"; nonnegative=true)
    length(qvec) == length(qref) ||
        throw(ArgumentError("quantiles and quantile_costs must have equal lengths"))
    _metric_quantile_order(qvec, qref)
    pvec = _metric_values(prices, "price")
    pref = _metric_values(profit_ratios, "reference profit")
    length(pvec) == length(pref) ||
        throw(ArgumentError("prices and profit_ratios must have equal lengths"))
    upper = profit_unit == :fraction ? 1 : 100
    all(p -> 0 <= p <= upper, pref) ||
        throw(ArgumentError("reference profit values must be in [0,$upper] for profit_unit=$profit_unit"))
    if profit_unit == :percent
        for i in eachindex(pref)
            before = pref[i]
            pref[i] /= 100
            before > 0 && pref[i] == 0 &&
                throw(ArgumentError("positive percent profit must not underflow conversion to fraction"))
        end
    end
    (isnothing(mean_reference) && isempty(qvec) && isempty(pvec)) &&
        throw(ArgumentError("at least one mean, quantile or profit summary is required"))
    mean_estimate = isnothing(mean_reference) ? nothing : average_cost(estimate)
    qest = [cost_quantile(estimate, q) for q in qvec]
    pest = [profit_ratio(estimate, p) for p in pvec]
    return (mean_cost_estimate=mean_estimate, mean_cost_reference=mean_reference,
            mean_cost_error=isnothing(mean_reference) ? nothing : mean_estimate-mean_reference,
            quantiles=qvec, quantile_estimates=qest, quantile_references=qref,
            quantile_errors=qest .- qref, prices=pvec, profit_estimates=pest,
            profit_references=pref, profit_errors=pest .- pref)
end
