# saboteur

Mutation testing for Ruby 3.3+.

saboteur makes small deliberate changes to your methods ("mutations"), runs
only the tests that execute each changed method, and reports the changes no
test notices ("survivors"). Each survivor points at a missing test or at code
that does not matter.

Status: pre-release (0.0.1 reserves the name). Nothing works yet.

## Planned features

- Test selection from per-test line coverage, cached.
- Diff mode for pull requests: `saboteur run --since origin/main`.
- Coarse mutations first (method body -> `nil` / `raise`); fine-grained only if those are caught.
- Reports in the open Stryker mutation-testing-report JSON format.
- RSpec first, Minitest next, optional Rails integration.
- A plug-in point for external mutation sources.

## Usage (planned)

```sh
gem install saboteur
saboteur run
saboteur run --since origin/main
saboteur run --subject 'Billing::Invoice#total'
```

See [docs/design.md](docs/design.md) for how it works.

## Requirements

Ruby 3.3 or newer on Linux or macOS (needs `fork`).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Commits need a DCO `Signed-off-by` line.

## License

MIT. Copyright (c) 2026 Vamsi Pavan Mahesh Gunturu. See [LICENSE](LICENSE).
