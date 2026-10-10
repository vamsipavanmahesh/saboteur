# saboteur vs mutineer: Phase 0 (targets)

Status: done, waiting for review (STOP).
Date: 2026-10-10. All numbers in this file are measured unless marked
"estimate".

## Frozen inputs

| item | value |
|------|-------|
| SABOTEUR_REF | 2b6ec02 (exported with `git archive`, used through a path gem; later repo commits cannot leak in) |
| MUTINEER_VERSION | 1.6.0 (released 2026-10-08, MIT, Ruby >= 3.4) |
| Hardware | Apple M3 Max, 14 cores, 36 GB RAM |
| OS | macOS 14.3 (23D56), arm64 |
| Ruby | 3.4.3 (gems, human-essentials); 4.0.0 (lobsters, which pins it) |
| Postgres | 16.11 in Docker (human-essentials test DB only) |
| SQLite | sqlite3 gem 2.9.5 (lobsters) |

Each tool runs on the same Ruby as its target, so both tools share one Ruby
per target.

## Targets

| target | role | commit | framework | Ruby | DB | code LOC (non-blank, non-comment) | source files | tests | suite time |
|--------|------|--------|-----------|------|----|------|----|-------|-----------|
| addressable | RSpec gem | d298c9f | RSpec 3.13.6 | 3.4.3 | none | 6,657 (a large share is IDNA data tables) | 7 | 1,433 examples (5 pending) | 0.5 s |
| rack | Minitest gem | a9833c8f | Minitest 6.0.6 | 3.4.3 | none | 5,829 | 50 | 1,244 runs (2 skips) | ~4 s wall |
| lobsters | Rails app, SQLite | ede993e0 | RSpec 3.13.5, Rails 8.1.3.1 | 4.0.0 | SQLite (4 files: primary, cache, queue, rack_attack) | 8,793 (app + lib) | 131 | 899 examples | 15 s |
| human-essentials | Rails app, Postgres | d6f8290 | RSpec 3.13.6, Rails 8.1.4 | 3.4.3 | Postgres 16 | 12,871 (app + lib) | 292 | 2,415 examples (1 pending), system specs excluded | 132 s |
| hashie | spare RSpec gem | 9c81e83 | RSpec 3.13.6 | 3.4.3 | none | 2,094 | 41 | 719 examples | 0.1 s |

Suite time is RSpec's own duration (median of 3). rack's is wall time
around `rake test:regular`.

## Green runs (3 each, under script/watchdog)

| target | run 1 | run 2 | run 3 | flaky |
|--------|-------|-------|-------|-------|
| addressable | 0 failed | 0 failed | 0 failed | none |
| rack | 0 failed, 0 errors | 0 / 0 | 0 / 0 | none |
| lobsters | 0 failed | 0 failed | 0 failed | none |
| human-essentials | 0 failed | 0 failed | 1 failed | 1 |
| hashie | 0 failed | 0 failed | 0 failed | none |

Excluded flaky test (both tools exclude it):

- human-essentials `./spec/services/reports/diaper_report_service_spec.rb[1:1:2]`
  ("acquisition report should return the proper results on #report").
  Failed only in run 3 with a wrong report entry, which looks data or date
  dependent (inference).

Raw numbers: raw/phase0-suite-runs.json.

## Setup notes and workarounds (apply to both tools)

- Each target gets a bench-only `Gemfile.bench` that evaluates the target's
  own Gemfile and adds saboteur (path, frozen copy) and mutineer 1.6.0. The
  target's Gemfile and lockfile are not edited.
- lobsters pins Ruby 4.0.0, and lobsters became SQLite-only in 2026-07, after
  its move to Ruby 4.0. No RSpec + SQLite Rails app on Ruby 3.4 was found,
  so Ruby 4.0.0 was built from the official tarball (SHA-256 checked).
- lobsters: libvips cannot be installed here (Homebrew 7 treats macOS 14
  as Tier 3 and builds from source). `ruby-vips` is loaded with
  `require: false`. No test needed it (899/899 pass). `app/models/story_image.rb`,
  the only file that uses Vips, is left out of the mutated sources.
- lobsters: the CI test credentials are copied into config/ as its CI does,
  and config/database.yml comes from the sample.
- human-essentials: Postgres in Docker on port 5433; system specs excluded
  (they need a browser), as in saboteur's earlier Phase 4 validation.
- addressable: IDNA_MODE=pure, so the native idn-ruby gem is not needed.

## saboteur bugs found so far (logged; ref stays frozen)

1. saboteur requires `fiddle` without declaring it in its gemspec. Ruby 4.0
   removed fiddle from the default gems, so saboteur fails to load on Ruby 4.0
   unless the target bundle has fiddle. Workaround: `gem "fiddle"` in the
   lobsters Gemfile.bench.

## Open questions for review

1. rack (Minitest): saboteur supports RSpec only, so on rack it can only
   report "unsupported". Options: keep rack as a mutineer-only data point
   (this counts as a mutineer win on framework support), or replace it with
   hashie as a second RSpec gem so both tools produce numbers. Recommendation:
   keep rack for the features table and the framework win, and add hashie for
   the measured comparisons.
2. Is a Ruby 4.0 target acceptable? Both tools run on the same Ruby there,
   but saboteur has never been validated on 4.0, so a 4.0 failure would be
   a saboteur result.
