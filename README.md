# saboteur

Mutation testing for Ruby 3.3+.

saboteur makes small deliberate changes to your methods (mutants), runs only
the tests that execute each change, and reports the changes no test notices
(survivors). Each survivor points at a missing test or at code that does not
matter.

Status: pre-release, not yet published. Works on RSpec suites of plain gems;
Rails support is in progress. RSpec only, by design for v1.

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
```

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
reeval: class_eval          # or nesting; see docs/design.md 6.1
timeout_factor: 3           # per-mutant deadline = factor x neutral-check time
timeout_min: 5
max_memory_mb: 2048         # memory growth cap per mutant process tree
max_processes: 64
ignore_file: .saboteur-ignore.yml
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

## Requirements

Ruby 3.3 or newer on Linux or macOS (it needs `fork`).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Commits need a DCO `Signed-off-by` line.

## License

MIT. Copyright (c) 2026 Vamsi Pavan Mahesh Gunturu. See [LICENSE](LICENSE).
