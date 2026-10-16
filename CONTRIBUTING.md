# Contributing

Describe the mathematical assumption behind a change and add tests with an
independently known answer. Keep data, units, initialization and corporate-action
assumptions explicit. Avoid unlicensed real-market fixtures and unpublished
claims about software equivalence.

Run `julia --project=. --check-bounds=yes -e 'using Pkg; Pkg.test()'` and
`julia --project=. examples/basic.jl`. Build documentation as described in
`docs/src/index.md`. CI collects coverage and builds documentation; inspect
its actual results before release. Test the lowest supported Julia version.

Changes to exported behavior need documentation and a version decision.
Keep the package UUID stable. Use local accessors instead of mutating stored
vectors. New daily models return ChipDistribution on the requested grid; new
turnover models return a finite replacement fraction in [0,1].

Disclose significant AI contributions. A human maintainer must review and
understand all contributed code before General registration. Track release
work in `DEVELOPMENT_REPORT.md` and `docs/src/registration.md`.
