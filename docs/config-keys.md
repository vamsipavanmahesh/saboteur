# Config keys, defaults and the first run

Every `config/saboteur.rb` key, its default, who ever needs to change it,
and what a first run should use. The audit behind this table is #333.

The short version: a first run decides only what to mutate (`include`) and
how much parallelism is safe (`jobs`). On Rails it also sets `require` to
the boot file and `rails = true`. Every other key has a safe default; touch
it when a real run gives you a reason, not before. The generated configs
(`rails generate saboteur:install`) already follow this: they set only the
first-run rows and point here for the rest.

## Scope: what gets mutated

| Key | Default | Who changes it | First run |
| --- | --- | --- | --- |
| `include` | `["lib/**/*.rb"]` | Every app whose code is not under `lib/` | Decide: `["app/**/*.rb"]` on Rails |
| `exclude` | spec/test globs under `lib/` | Apps with empty base classes or vendored suites | Default; add entries when a file mutates nothing useful |
| `require` | `[]` | Rails apps | Rails only: `["./config/environment"]` |
| `rails` | `false` | Rails apps | Rails only: `true` |
| `integration` | `"rspec"` | Minitest users (see [Minitest](minitest.md)) | Default |
| `subjects` | `[]` | CLI scoping (`--subject`) | Default; scope from the CLI |
| `since` | `nil` | PR loops | Default; pass `--since` in the PR job, not in the config |
| `all` | `false` | Whole-project runs | Default; use the `audit` preset |
| `sources` | `["builtin"]` | Custom mutation engines | Default |
| `whole_file` | `[]` | Opt-in to whole-file constant replay | Default |

## Test selection

| Key | Default | Who changes it | First run |
| --- | --- | --- | --- |
| `tests` | `[]` | Runs that name their specs (`--test`) | Default; let inference guess |
| `test_command` | `nil` | Suites with a non-standard runner | Default |
| `test_selection` | `"auto"` | Manual selection control | Default |
| `guess_tests` | `false` | Deprecated inference alias | Default |
| `rspec_args` | `[]` | Suites needing extra RSpec flags | Default |
| `allow_focus` | `false` | Suites that keep focused specs | Default |
| `hooks` | `[]` | Custom lifecycle hooks (see [Recipes](recipes/README.md)) | Default |

## Execution and resources

| Key | Default | Who changes it | First run |
| --- | --- | --- | --- |
| `jobs` | `1` | Everyone | Decide: `4` is the generated pick; keep `1` when specs share external state |
| `baseline_passes` | `2` | Flaky suites and the `pr` preset (uses 1) | Default |
| `coverage_parts` | `1` | Suites whose coverage build is slow | Default |
| `timeout_factor` | `3.0` | Slow suites | Default |
| `timeout_min` | `5.0` | Slow suites | Default |
| `baseline_timeout` | `300.0` | Slow suites | Default |
| `coverage_timeout` | `3600.0` | Very large suites | Default |
| `max_memory_mb` | `2048` | Small containers | Default |
| `max_processes` | `64` | Small containers | Default |
| `max_mutants_per_method` | `100` | Very large methods | Default; the cap is why a PR score is not a project score |
| `max_duration` | `nil` | Budgeted runs (the `pr` preset uses `10m`) | Default |
| `max_duration_ok` | `false` | Budgets that may pass incomplete | Default |
| `fail_fast` | `false` | Quick feedback loops | Default |
| `seed` | `1` | Reproducing a reported run | Default |
| `shard` | `nil` | Sharded CI (see [sharding](guides/sharding.md)) | Default |
| `matrix` | `false` | Operator-matrix CI | Default |
| `incremental` | `false` | Local iteration | Default; run without it on main now and then |
| `resume` | `nil` | Keep verdicts in a directory across runs (`--resume DIR`); anyone who can write it can forge verdicts, so restore it only from a trusted-branch cache, never from fork PRs | Default |
| `cache` | `true` | A suspect cached run | Default |
| `cache_dir` | `".saboteur"` | Non-standard cache locations | Default |
| `partial_coverage` | `"off"` | Experimental: `"shadow"` also rebuilds the map partially after a cache miss and writes a comparison report; the full map is still the one used; never reused when RSpec selects examples from `spec/examples.txt` (`--only-failures`, `--next-failure`, however RSpec was given them) | Default |
| `coverage_recorder` | `"coverage"` | Experimental: `"trace"` builds the per-test map with a TracePoint for lines and methods and one Coverage read per spec file for branches; the build is faster, and a branch can be credited to a few more tests than ran it, so selection only widens | Default |
| `fingerprint_extra` | `[]` | Fixtures the map fingerprint cannot see | Default |

## Safety

| Key | Default | Who changes it | First run |
| --- | --- | --- | --- |
| `hazard` | destructive-call denylist | Apps with their own destructive helpers | Default; extend, never shrink |
| `allow_hazardous` | `false` | Nobody on a first run | Default |
| `sandbox` | `true` | Hardened CI (`"strict"`), macOS (`"seatbelt"`) | Default |
| `sandbox_writable` | `[]` | Suites that write outside tmp | Default |
| `allow_db_hosts` | `[]` | Disposable test databases (#258) | Default |
| `reeval` | `"nesting"` | Constant-replay tuning | Default |

## Gates and reporting

| Key | Default | Who changes it | First run |
| --- | --- | --- | --- |
| `threshold` | `nil` (binary gate) | Teams graduating from all-or-nothing | Default; read survivors before gating on a score |
| `score_gates` | `[]` | Subtrees held to a stricter floor (#473) | Default |
| `max_timeouts` | `nil` | CI guards | Default |
| `max_errors` | `nil` | CI guards | Default |
| `flaky_check` | `"off"` | Flaky-prone suites (costs a confirmation run per survivor) | Default |
| `json_report` | `".saboteur/report.json"` | Custom report locations | Default |
| `html_report` | `".saboteur/report.html"` | Custom report locations | Default |
| `score_history` | `nil` | Trend tracking (`badge`, `trend`) | Default |
| `verbose` | `false` | Debugging a run | Default |

## Files and internals

| Key | Default | Who changes it | First run |
| --- | --- | --- | --- |
| `ignore_file` | `"config/saboteur_ignore.rb"` | Non-standard layouts | Default |
| `custom_map` | `"config/saboteur_custom_map.rb"` | Monorepos (see [the monorepo guide](guides/monorepo-and-custom-map.md)) | Default |
| `arid` | arid-call patterns | Advanced arid tuning | Default |
| `operators` | `[]` | Operator tuning (`audit` uses `all`) | Default |
| `exclude_operators` | `[]` | Operator tuning | Default |

## What changes as trust builds

The `pr` preset (`--baseline-passes 1 --max-duration 10m --since`) is the
fast loop once the first clean run lands; `audit` is the whole-project
sweep for main or nightly. Thresholds, score gates and `flaky_check` are
second-week decisions: they all need a few real runs of survivor reading
before the number means anything ([Best practices](best-practices.md)).
