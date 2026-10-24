# Local quality and name checks

Internal registration-quality notes. This record is not part of the user documentation.

## Renamed-package preflight (2026-10-24)

`AShareCostDistributions` passed AutoMerge 1.1.1's identifier,
capitalization, length, ASCII, Julia-name, exact-name, and default distance
checks against General registry tree
`5a199e4cf222234ad406c0cbd714f1529e3f5ffb`. The registry snapshot contained
14,541 package names including JLL packages and 12,703 excluding them. There
was no case-insensitive exact collision and no package within the visual
distance gate. The closest case-sensitive name was
`PhaseTypeDistributions` at Damerau-Levenshtein distance 7.

The checks used Julia 1.10.12, RegistryCI 11.0.0, AutoMerge 1.1.1,
RegistryInstances 0.1.0, VisualStringDistances 0.1.1, and StringDistances
0.11.3. They are a reproducible preflight, not a reservation of the name or a
substitute for the checks run on the registration pull request.

## Former-name evidence

The Aqua checks and initial name checks below retain their dated evidence;
the renamed-package preflight above records the current name check.
They do not establish
General approval, remote CI success, or agreement with a market-data provider
or trading application.

## Aqua quality assurance

Aqua 0.8.18 is a test-only dependency. The final package tests on
2026-10-16 execute `Aqua.test_all(AShareChips; undocumented_names=true)`.
Both Julia versions passed every applicable default check: 11 assertions on
1.10.12 and 12 on 1.13.1. No default check was disabled or ignored.
The optional public-docstring check is a no-op on Julia < 1.11 according to
[Aqua's documented behavior](https://juliatesting.github.io/Aqua.jl/stable/undocumented_names/).

Checks cover method ambiguities, unbound type parameters, undefined exports,
test-project consistency, stale dependencies, compatibility bounds, type piracy
and persistent tasks. See the [official test_all documentation](https://juliatesting.github.io/Aqua.jl/stable/test_all/).
Numerical, import, event and report tests are in the same package test run.
Final source, test, example and fixture SHA-256 values and raw logs are retained
in the deliverable validation directory, as described in the development report.
Earlier independent audit logs describe the earlier source; they are not used
as an attestation of this revised implementation. These checks cannot replace
human review or real-market calibration.

## Official package-name checks

The local name checks loaded complete official packages: **RegistryCI 11.0.0**,
**AutoMerge 1.1.1**, **RegistryInstances 0.1.0**,
**StringDistances 0.11.3** and **VisualStringDistances 0.1.1**. They did not use a
custom replacement for the official checker. RegistryCI 11 moved its AutoMerge
functionality to the separate `AutoMerge` package; accessing
`RegistryCI.AutoMerge.meets_distance_check` produces an explicit migration
exception. The current official call is:

```julia
using RegistryCI, RegistryInstances, AutoMerge
registry = RegistryInstance(path_to_general_toml)
names = AutoMerge.get_all_pkg_names(registry; keep_jll=false)
AutoMerge.meets_distance_check("AShareChips", names)
# (true, "")
```

This follows the current
[official RegistryCI source and usage guidance](https://github.com/JuliaRegistries/RegistryCI.jl/blob/master/docs/src/guidelines.md).
The fixed General snapshot was commit
[`019c873b5d0e10da96dc6fbed954a530703cf1c0`](https://github.com/JuliaRegistries/General/commit/019c873b5d0e10da96dc6fbed954a530703cf1c0),
dated **2026-10-15 19:42:58 Asia/Shanghai**; its registry tree was
`5a199e4cf222234ad406c0cbd714f1529e3f5ffb`. The package-server archive SHA-256
was `6d9d6d62196531906e7fa56a57550618490bb93faf1dc17de96eeae088c0eeea`.
It contained **14,541** package names, including **12,703** non-JLL names.
This snapshot is later than the separate ecosystem survey snapshot.

| Official local check | Result |
|:--|:--|
| Valid identifier, capitalization, ASCII, minimum name length, Julia prefix/suffix rules | All returned `(true, "")` |
| Exact case-insensitive collision against all names, including JLLs | `(true, "")` |
| `AutoMerge.meets_distance_check`, with unmodified default thresholds | `(true, "")` |

The installed official checker requires case-sensitive Damerau–Levenshtein
distance greater than 2 and lowercased distance greater than 1. It checks
normalized visual distance against 2.5 only for names with case-sensitive edit
distance at most 4. This gate is part of the
[official implementation](https://github.com/JuliaRegistries/RegistryCI.jl/blob/master/AutoMerge/src/guidelines.jl).
The closest case-sensitive distance for `AShareChips` was **6**, tied by
`Arrhenius`, `Shapefile`, `ShareAdd`, `ShortCodes` and `SparseGrids`; therefore
there were no candidates inside the official visual gate. As an additional
check that the visual engine actually ran, the same official normalized visual
function was evaluated against `Arrhenius`, yielding **16.047652181837403**.
That supplemental evaluation is not an extra registry requirement.

The final name run exited successfully. During the initial tool precompile,
HTTP reported that the sandbox prohibited its local socket workload; HTTP
explicitly ignored that workload error, and the name checker completed. The
final recorded name run has no such diagnostic. Names and rules can change;
rerun the check against the registry snapshot selected at release time.

## Reproduction and remaining gates

The local audit uses isolated `work/release-checks/` environments and depots.
Registry tools are not runtime or test dependencies of AShareChips. Scripts,
source hashes and raw logs are retained in that local audit directory. Commands
were run from the workspace root:

```sh
JULIA_DEPOT_PATH="$PWD/work/release-checks/depot:$PWD/work/depot-docs" \
  work/runtime/1.10.12/julia-1.10.12/bin/julia --startup-file=no \
  --project=work/release-checks work/release-checks/name_checks.jl

JULIA_DEPOT_PATH="$PWD/work/release-checks/depot:$PWD/work/depot-docs" \
  work/runtime/1.10.12/julia-1.10.12/bin/julia --startup-file=no \
  --project=work/release-checks \
  -e 'using Pkg; Pkg.offline(true); Pkg.resolve(); include("work/release-checks/aqua_checks.jl")'

JULIA_DEPOT_PATH="$PWD/work/release-checks/depot:$PWD/work/depot-docs" \
  work/runtime/1.13.1/julia-1.13.1/bin/julia --startup-file=no \
  --project=work/release-checks/env-1.13 \
  -e 'using Pkg; Pkg.offline(true); Pkg.resolve(); include("work/release-checks/aqua_checks.jl")'
```

The fixed package-name log remains `name-checks-1.10.12.log` with SHA-256
`8e4031ca1780268d3de22a74591ff1b48238dc78b740cee45831b1445188b865`.
Aqua is now recorded by the complete final `pkgtest-final-*.log` files rather
than the earlier independent source audit. See the development report and
validation summary for the tested source hashes and full counts.

These local audit paths are outside the package and are not required to install
it. A new checkout can reproduce the package quality checks using
`julia --project=. -e 'using Pkg; Pkg.test()'`; reproduce the official name check
in an independent environment after adding `RegistryCI`, `AutoMerge` and
`RegistryInstances` and supplying a current General registry path.

Local quality and name checks cover only part of publication readiness. The
development source is now public; the [development report](https://github.com/3142115360-web/AShareChips.jl/blob/main/DEVELOPMENT_REPORT.md)
records the actual remote runs. Human maintainer review was confirmed by the
user on 2026-10-18. Selecting a release commit, Registrator submission and
General review remain separate steps. General's
[requirements and LLM policy](https://github.com/JuliaRegistries/General/blob/master/README.md)
require a human maintainer to understand and manually review AI-assisted code.

## Release-preparation name recheck (2026-10-18)

The official checks were rerun against General commit
[`1b5fd14672b1533feabe49f15ff7f50b3f0a3a0a`](https://github.com/JuliaRegistries/General/commit/1b5fd14672b1533feabe49f15ff7f50b3f0a3a0a),
with tree `884041d15038573e205739c11e39ab405d16a60d`. Its Registry.toml
SHA-256 was `52cfb4843b19e0b27c9b2adb6ba79aec8c67f9832022d6acc053ee9d2756efa0`.
It contained 14,574 packages including JLLs and 12,698 non-JLL packages.

AutoMerge 1.1.1 was still the latest registered version in that snapshot.
All five basic name checks, the exact collision check and the default distance
check returned `(true, "")`. The package UUID was unused. The closest edit
distance remained 6, so there were no candidates in the official visual gate.
The actual run exited 0. An initial run lacked OpenSSL_jll in the selected
cache; the successful retry used an existing complete cache without disabling
checks. The isolated local evidence is retained under
`work/registration-preflight/`; it is not a package dependency.

This result does not reserve a name or establish General approval. The latest
merged implementation's remote test results are in the development report.
