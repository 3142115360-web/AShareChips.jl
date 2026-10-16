"""
    compare_history(series::BarSeries, reference::ReferenceSeries; grid,
                    matching=:strict, require_symbol_match=true,
                    quantiles=[0.1, 0.5, 0.9], prices=nothing, kwargs...)

Simulate daily cost histograms and compare matching reference dates. Price-basis
labels must agree. By default both security symbols must be known and equal;
`require_symbol_match=false` permits unknown labels as a caller assertion, but
known unequal symbols are always rejected. Labels cannot verify data provenance.

`:strict` requires identical dates. `:intersection` compares common dates and
reports `estimate_only_dates` and `reference_only_dates`; no common date is an
error. No sorting, date filling or reference rebasing occurs. Missing reference
days still participate in the simulation; they are not removed from the model.
Each comparison defaults to that observation's close as its sole profit price.
Other model/initial/adjustment keywords are forwarded to `chip_history`.

Return `(rows, estimate_only_dates, reference_only_dates, symbol, price_basis)`.
Rows contain `date`, `close` and the fields from `compare_distributions`. q/price
iterators are materialized once and copied into each result. Numerical agreement
does not recover real account holdings or an unpublished market-terminal model.
"""
function compare_history(series::BarSeries, reference::ReferenceSeries;
                         grid::PriceGrid, matching::Symbol=:strict,
                         require_symbol_match::Bool=true,
                         quantiles=[0.1,0.5,0.9], prices=nothing, kwargs...)
    matching in (:strict,:intersection) || throw(ArgumentError("matching must be :strict or :intersection"))
    series.price_basis == reference.price_basis || throw(ArgumentError("price bases must agree before comparison"))
    known = !isnothing(series.symbol) && !isnothing(reference.symbol)
    known && series.symbol != reference.symbol && throw(ArgumentError("security symbols do not match"))
    require_symbol_match && !known && throw(ArgumentError("both series need known symbols, or explicitly set require_symbol_match=false"))
    matching == :strict && series.dates != reference.dates && throw(ArgumentError("strict comparison requires identical observation/reference dates"))
    references = Dict(date=>i for (i,date) in pairs(reference.dates))
    estimate_dates = Set(series.dates)
    estimate_only = [date for date in series.dates if !haskey(references,date)]
    reference_only = [date for date in reference.dates if !(date in estimate_dates)]
    common = [i for i in eachindex(series.dates) if haskey(references,series.dates[i])]
    isempty(common) && throw(ArgumentError("there are no common comparison dates"))
    qvec = _comparison_values(quantiles,"quantile";unit_interval=true)
    pvec = isnothing(prices) ? nothing : _comparison_values(prices,"price")
    history = chip_history(series;grid,kwargs...)
    rows = [merge((date=series.dates[i],close=series.bars[i].close),
                  compare_distributions(history[i],reference.distributions[references[series.dates[i]]];
                    quantiles=qvec,prices=isnothing(pvec) ? [series.bars[i].close] : pvec))
            for i in common]
    return (rows=rows,estimate_only_dates=estimate_only,reference_only_dates=reference_only,
            symbol=series.symbol,price_basis=series.price_basis)
end
