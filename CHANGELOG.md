# Changelog

## 0.1.0 (unreleased)

- Cost histograms with uniform, triangular and empirical trading models.
- Linear/exponential replacement, explicit initial state, chronological history.
- Conservative affine rebasing before each turnover update.
- Histogram mean, profit CDF, inverse CDF and equal-tail concentration.
- Synthetic analytical/regression tests, documentation and CI workflows.

Not yet registered. Proprietary terminal parity, broader real-market validation
and corporate-action validation remain future work; no trading signals are included.

### Continued release preparation

- Explicitly dated single-security observations and simple delimited-file import.
- Price/turnover basis metadata, strict dates and double-adjustment prevention.
- CDF/Wasserstein/quantile/profit comparisons across different grids.
- Grid sensitivity experiments and a configurable daily-result CSV example.
- Lower triangular-model allocations and reproducible synthetic benchmarks.
- Aqua checks in the package test target; official AutoMerge name checks recorded.

### Reference workflow and numerical boundary review

- Explicit-unit reference histogram import and dated corporate-action files.
- Security/basis/date-aligned historical comparisons and missing-date reporting.
- Local kernel integration retaining thin triangular tails.
- Rejection of positive inputs/masses that underflow Float64.
- Stable CDF/survival differences plus exact-rational fallback for rare tiny mass.
- Non-overwriting report publication and writer-failure cleanup.
- Chinese human-maintainer review map and independent numerical oracle checks.

### Scalar reference comparisons

- Compare supplied means, quantile costs and profit summaries with explicit units and evaluation prices.
- Strict dated CSV example with complete-history simulation, missing-date reporting and non-overwriting output.
- Explicit `provider_reported` turnover basis for an unverified source denominator.
- Independent scalar oracles and actual public-market model comparison; no terminal parity claim.
- Narrow TagBot contents-write permission, leaving test/documentation tokens read-only.
