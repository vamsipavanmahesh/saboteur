# saboteur

Mutation testing for Ruby 3.3+.

saboteur makes small deliberate changes to your methods (mutants), runs only
the tests that execute each change, and reports the changes no test notices
(survivors). Each survivor points at a missing test or at code that does not
matter.

Status: an early release (0.2.0). Tested on the RSpec suites of plain gems
(dry-inflector, tty-color, hashie, addressable) and of two Rails 8.1 apps:
human-essentials on Postgres (4,080 mutants, 6 workers) and lobsters on
SQLite, both on macOS. Not yet tried on MySQL or older Rails versions. RSpec
only, by design.

## What makes it different

- **Tests picked per mutant by line coverage.** Each mutant runs only the
  tests that executed the changed statement. A change no test reaches is
  reported as "no coverage", not as a survivor.
- **Likeliest killers first.** Tests that killed earlier mutants of the same
  method run first, then the fastest; the first failure stops the run.
- **Coarse first.** Each method's body is first replaced with `nil` and with
  `raise`. If a test suite does not notice that, saboteur reports it and
  skips the fine-grained mutants for that method.
- **Diff mode.** `--since origin/main` mutates only methods changed on a branch.
- **Safe to run.** Every mutant runs in a supervised child; anything it
  starts is tracked and killed, with deadline, memory and process caps.
- **Open report format.** JSON in the Stryker mutation-testing-report schema.
- **Pluggable mutation sources.** Add your own mutants by file and byte range.

## Usage

```sh
bundle exec saboteur run                          # whole project
bundle exec saboteur run --since origin/main      # methods changed on this branch
bundle exec saboteur run --subject 'Billing::Invoice#total'
bundle exec saboteur run --subject Billing        # a namespace
bundle exec saboteur run --incremental            # reuse verdicts whose inputs did not change
bundle exec saboteur run --seed 1234              # repeat a run that used seed 1234
```

Every test run starts from the same random seed (1 by default), so tests
that use `rand` see the same values in each mutant's run and in the check
that confirms a kill. The report prints the seed; pass it to `--seed` to
repeat a run.

`--incremental` reuses an earlier verdict only while the method, the mutant,
its covering tests and their files, the lockfile and the config are all
unchanged. It cannot see a change in a method this one calls, so run without
it now and then (and in CI on the main branch).

Output: counts per status, the score, timing, and a unified diff for every
survivor. The JSON report goes to `.saboteur/report.json`.

Exit codes: 0 no survivors (or all on the ignore list), 1 survivors,
2 bad configuration, 3 the tool failed.

## Configuration

`.saboteur.yml` in the project root; CLI flags override it.

```yaml
include: [lib/**/*.rb]
exclude: [lib/my_gem/version.rb]
require: []                 # boot files, e.g. ./config/environment
reeval: nesting             # or class_eval; see docs/design.md 6.1
timeout_factor: 3           # per-mutant deadline = factor x its tests' recorded time
timeout_min: 5
max_memory_mb: 2048         # memory growth cap per mutant process tree
max_processes: 64
ignore_file: .saboteur-ignore.yml
seed: 1                     # Ruby's random seed in every test run
```

### Ignoring a survivor

Every survivor is printed with a digest. Accept it with a reason:

```yaml
# .saboteur-ignore.yml
- subject: "Billing::Invoice#total"
  mutation: "1a2b3c4d5e6f7a8b"
  reason: "equivalent: amounts are always whole cents"
```

An entry without a reason is rejected.

### SimpleCov

saboteur needs Ruby's `Coverage` for itself. Disable SimpleCov for the run
(most projects already guard it with an environment variable).

## Extending

Public API, stable across minor versions:

- `Saboteur::MutationSource::Base#mutations_for(subject)` returning
  `Saboteur::MutationSource::Mutation` objects made of `Edit`s (file, byte
  range, replacement). Register with `sources: [builtin, path.rb:ClassName]`.
- `Saboteur::Integration::Base` for other test frameworks (RSpec is the
  only one that ships).
- `Saboteur.hook(:before_boot | :after_boot | :before_fork | :after_fork |
  :around_mutant)` in files listed under `hooks:`.

## How it works

See [docs/design.md](docs/design.md). Validation results are in
[docs/validation](docs/validation), research in [docs/research](docs/research),
and the project checklist in [docs/status.md](docs/status.md).

## Benchmark

A small, non-exhaustive comparison with [mutineer](https://github.com/davidteren/mutineer)
1.6.0 on four RSpec projects (two libraries, two Rails apps). Each configuration
ran once on sampled files, so treat the numbers as indicative.

| Metric | saboteur | mutineer |
|---|---|---|
| Fake kills (lobsters) | 0 of 20 checked | 8 of 8 checked |
| Rails app with 6 workers | yes, same verdicts as 1 worker | 1 worker only |
| Runs on the Postgres app | yes | no |
| Time per mutant, hashie | 0.008 s | 0.092 s |
| Peak memory, hashie | 595 MB | 471 MB |
| Choice of operators, CI features | fixed set, fewer | 20 operators, baseline, HTML, GitHub Action |

Full results, method and limitations:
[benchmark page](https://vamsipavanmahesh.github.io/saboteur/benchmark/).
Scripts and raw data: [bench/vs-mutineer](bench/vs-mutineer).

## Requirements

Ruby 3.3 or newer on Linux or macOS (it needs `fork`).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Commits need a DCO `Signed-off-by` line.

## Acknowledgements

Thanks to [Glomo](https://glomo.one) for providing the AI tokens used to build saboteur.

## License

MIT. Copyright (c) 2026 Vamsi Pavan Mahesh Gunturu. See [LICENSE](LICENSE).
