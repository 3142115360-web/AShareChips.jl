# Mathematical model

## Probability state and recurrence

Grid edges `e₁ < … < e_(B+1)` are finite and nonnegative. Each bin has probability `mᵢ ≥ 0`, with total mass 1 and constant density `mᵢ/(e_(i+1)-eᵢ)` inside the bin. Bins need not have equal widths. Prices use yuan per share, or another unit chosen consistently by the caller.

```math
C_t(p)=(1-\alpha_t)C_{t-1}^{\mathrm{adj}}(p)+\alpha_tD_t(p).
```

The default linear effective turnover is `α=clamp(kτ,0,1)`; the exponential alternative is `α=1-exp(-kτ)`. Turnover `τ` is a nonnegative fraction and may exceed 1; `k` is nonnegative. The model assumes previous holdings exit proportionally at every cost level. It does not model holding age, price-dependent selling or investor behaviour.

Without `initial`, the first state is `C₁=D₁`, regardless of first-day turnover. With `initial`, the first day also follows the recurrence. Without adjustments, the surviving weight of initialization error is `∏(1-α_t)`. A short observation window can retain substantial initialization bias.

## Daily cost distributions

- `UniformModel`: uniform on `[L,H]`.
- `TriangularModel`: support `[L,H]` and mode `M`. The default is `M=(L+H+close)/3`; alternatives use the close or caller-supplied VWAP.
- `EmpiricalModel`: allocates bin probabilities from trade prices and volume weights. A different model may be supplied for each day.

For a nondegenerate triangle with an interior mode:

```math
f(p)=\begin{cases}
\frac{2(p-L)}{(H-L)(M-L)} & L\le p\le M,\\
\frac{2(H-p)}{(H-L)(H-M)} & M<p\le H,\\
0 & \text{otherwise}.
\end{cases}
```

`M=L` and `M=H` use the corresponding one-sided limits. A continuous model's bin mass is mathematically `F(e_(i+1))-F(eᵢ)`. The implementation integrates local density to avoid cancellation, then represents that mass uniformly within the bin. When `L=H`, or for empirical trade prices, mass enters the containing bin. An internal edge belongs to the bin on its right; the final edge belongs to the last bin.

No support is clipped. All daily trading ranges and all adjusted support with positive mass must fit inside the grid, or an error is raised. Coarse grids affect means, quantiles and profit ratios, particularly for single-price days and discrete trades. Spreading mass uniformly inside a bin does not imply trades occurred throughout it. Actual account costs also depend on earlier history, corporate actions, fees, taxes and which holdings were sold.

## Metrics

The mean is `Σ mᵢ(eᵢ+e_(i+1))/2`. The profit ratio is the histogram CDF `P(cost < price)`; under the uniform-within-bin representation, individual points have zero mass. Cost quantiles use the generalized inverse of that CDF, with linear interpolation inside positive-mass bins. `q=0/1` returns the endpoints of the positive-mass support; at a zero-mass plateau, the inverse returns the left endpoint.

Concentration reports an equal-tail interval with `lower=Q((1-c)/2)` and `upper=Q((1+c)/2)`, its absolute width `upper-lower`, and its relative width `(upper-lower)/(upper+lower)`. Relative width is a fraction; multiply by 100 for a percentage. Larger widths indicate greater dispersion. This is not a shortest covering interval, and equivalence with similarly named software indicators has not been established.

If extremely small subnormal Float64 prices cause both interval endpoints to round to zero, concentration raises an explicit error. Ordinary financial prices are far outside this numerical range.

## Extension and complexity

Subtype `AbstractDailyModel` and implement `daily_distribution`, returning a `ChipDistribution` on the same grid. Subtype `AbstractTurnoverModel` and implement `effective_turnover`, returning a finite value in `[0,1]`. Constructors validate finite nonnegative masses and normalize them.

Continuous daily models, updates and metrics take O(B) time. Empirical binning takes O(K log B), where K is the number of trades. Affine rebins scan ordered intervals and their overlapping bins. Final-state simulation retains O(B) numerical state. Ordinary input vectors are reused; other input iterators are collected into memory. Default models and adjustments do not allocate per-day lists. Retaining history additionally requires O(TB) storage. Version 0.1 makes no zero-allocation, arbitrary-precision, GPU or parallel multi-security performance guarantee.

## Numerical range and tiny tails

Continuous daily models integrate local densities to preserve triangular tails that could disappear when subtracting nearby CDF values. A nonzero input that converts to Float64 zero, or positive mass that underflows to zero during normalization, rebinning or recurrence, raises an explicit error. Extremely long histories may therefore require the caller to choose an explicit support window or another precision model; the package never drops tails automatically.

Ordinary comparisons use stable differences of CDF or survival probabilities. If a positive mass is smaller than machine epsilon, comparison and quantile calculations internally use exact rational normalization to retain small intermediate masses and distant tails hidden by large cumulative values. Outputs remain Float64. This uncommon path is slower and does not make the public API arbitrary-precision.
