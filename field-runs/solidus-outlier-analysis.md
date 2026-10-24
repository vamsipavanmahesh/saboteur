# Solidus scoped-run outliers: existing evidence review

Reviewed October 24, 2026. No new Solidus run was performed.

Both outliers ran tree `5b47ff22b600011f369e8da0de60bfe60bb27039` with the same recorded spec scope. They are direct-spec controls, not saboteur mutation runs.

| Recorded run | Seed | Examples / failures | External wall | RSpec duration |
| --- | --- | --- | --- | --- |
| pr6697-base-scope | 30913 | 226 / 0 | 751 s | 745.991 s |
| pr6701-head-scope | 1995 | 226 / 0 | 457 s | 451.032 s |

A single passing example accounts for most of each long run. The same examples were fast in the other recorded run of that identical tree:

| Example ID | pr6697-base-scope | pr6701-head-scope |
| --- | --- | --- |
| `./spec/models/spree/stock/availability_validator_spec.rb[1:3:1:1]` | 725.542 s, passed | 0.110 s, passed |
| `./spec/models/spree/stock/simple_coordinator_spec.rb[1:1:8:1]` | 0.120 s, passed | 431.237 s, passed |

The long durations are recorded inside RSpec, rather than explained by the roughly 5-6 s difference between suite duration and external wall. Two separate examples inflated in the two runs. This pair does not establish a repeatable slow path, rule out an order-dependent slow path, or prove a host-load explanation.

Cause remains unknown. The earlier suggestion that PR #6697's change explained the outliers is withdrawn. These records contain no CPU/wait/GC trace that would distinguish scheduling delays, I/O or runtime pauses from application behavior. No speed or performance-fix conclusion follows from them.

## Evidence

- `apps/solidus/logs/pr6697-base-scope-rspec.json`
- `apps/solidus/logs/pr6701-head-scope-rspec.json`
- `apps/solidus/reports/pr6697-base-scope/measurement.json`
- `apps/solidus/reports/pr6701-head-scope/measurement.json`

The evidence belongs to the original stopped preparation window. It does not advance the new sequential Lobsters-first mutation run.
