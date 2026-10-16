# Registration readiness

Requirements below were checked against official sources on 2026-10-15.
This package has not been submitted to General.

## General requirements and maintainer responsibilities

General requires an OSI-approved license in the package repository and forbids
dependencies on unregistered packages or unregistered dependency versions.
GitHub/GitLab packages must use Registrator. A functional package and public,
usable documentation are expected; empty or exclusively private-use packages
are unsuitable. Tests, CI, coverage tracking and documentation builds are
quality practices, not all independent AutoMerge gates.

General explicitly permits LLM-assisted development, but a human maintainer
must manually review and understand the generated code. Substantial AI
contributions should be disclosed in the README. This implementation is
AI-assisted; human review remains outstanding. An automated code review does
not satisfy that responsibility.

Source: [General README and LLM policy](https://github.com/JuliaRegistries/General/blob/master/README.md).

## Additional AutoMerge conditions

The automated path checks package naming, similarity to registered names,
repository naming (`AShareChips.jl.git`), a version without prerelease/build
suffixes, a root license, source filenames, and download/install/import success.
Julia and runtime dependency compatibility entries must have upper bounds.
The current `julia = "1.10"` means `>= 1.10.0, < 2.0.0`; it is not restricted
to the 1.10 series. Dates is the only runtime dependency and is part of Julia’s standard library; its compatibility is bounded. Aqua, Test and TOML are test-only dependencies.

`AShareChips` satisfies the basic spelling rules. The official AutoMerge name and distance checks passed against a fixed General snapshot; see [local quality evidence](quality.md). This does not reserve the name or guarantee registration approval. A failed
AutoMerge condition can need correction or manual registry review. New package
registration normally waits three days for community feedback.

Source: [RegistryCI AutoMerge guidelines](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/).

## Local release checklist

- [x] Stable package UUID, module/package name and initial version `0.1.0`.
- [x] MIT license in the package root.
- [x] Explicit Julia, Dates and test-dependency compatibility; Aqua included in the test target.
- [x] Test CI configured for Julia 1.10 and latest stable on Linux, and latest stable on Windows/macOS.
- [x] CI configured to retain raw Julia coverage files for 30 days.
- [x] Documentation CI configured to build HTML and execute doctests.
- [x] Local Pkg.test passed 1,124 assertions on Julia 1.10.12 and 1,125 on Julia 1.13.1; see the development report for logs and limits.
- [ ] Human maintainer review of algorithms, implementation, tests and license.
- [ ] Publish a public repository named `AShareChips.jl` and run its CI.
- [ ] Review coverage results and actual CI logs; workflow files alone do not prove success.
- [x] Run official name/distance checks against the recorded fixed General snapshot.
- [ ] Rerun name checks against the release-time registry snapshot.
- [ ] Select a release commit and confirm version, clean source and documentation.
- [ ] Install/configure Registrator and request registration.
- [ ] Resolve registry review, wait for merge, and verify installation through General.
- [ ] Configure repository Actions permissions and verify TagBot after registration.

Actual local test results belong in the development report. No remote CI,
full registration PR check or registry installation of AShareChips has been performed here.
Real-market comparison, data licensing and model validation also require
separate evidence; registration does not certify financial accuracy.

## Later registration procedure

After the maintainer has completed the checklist, install the Registrator
GitHub App and comment `@JuliaRegistrator register` on the selected package
commit. Registrator opens the General pull request. Trigger it again on a
corrected commit if needed. Registration publishes an immutable package version;
keep this package's UUID stable.

Source: [Registrator instructions](https://github.com/JuliaRegistries/Registrator.jl#via-the-github-app).

TagBot creates repository tags/releases after registry merge; it does not
register the package. The provided workflow uses the upstream pinned example
and `GITHUB_TOKEN`. Repository Actions permissions need setup. If a release
commit changes workflow files or tags must trigger documentation deployment,
review the upstream SSH-key/manual-release guidance first. Hosted documentation
and deploy keys have not been configured.

Source: [TagBot setup and troubleshooting](https://github.com/JuliaRegistries/TagBot).
