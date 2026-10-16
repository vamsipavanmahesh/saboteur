# Stability policy

What adopters can rely on, and how it changes.

## Stable public APIs

- **The agent JSON payload** (`saboteur run --agent`): the top-level keys,
  the `status`/`verdict` values and the `version` field. The payload carries
  an integer `version` (currently `1`).
- **The process exit codes**: `0` clean, `1` survivors to review, `2` usage
  or configuration error, `3` incomplete run or tool failure, `4` the
  `--max-duration` budget stopped the run. Presets that opt out of budget
  exits say so in `saboteur help`.
- **The machine report** (`.saboteur/report.json`): the
  [Stryker mutation-testing-report schema](https://mutationtesting.io/schema/mutation-testing-report-schema.json),
  which is versioned upstream.

Contract specs (`spec/saboteur/reporter/agent_contract_spec.rb`) fail when a
pinned key, the version or an exit code moves.

## How they change

- **Additive** changes (a new payload key alongside the existing ones, a new
  `incomplete` reason code) ship in a normal release with a CHANGELOG entry.
- **Breaking** changes (a renamed or removed key, a changed `status` or
  `verdict` value, a remapped exit code) require a bump of the payload
  `version`, a CHANGELOG entry under a `Changed` heading, and one release of
  overlap where the old and new shapes can coexist (for example the new key
  added one release before the old one is removed).

## Not covered

Human-facing terminal output, warning texts, the HTML report's layout and
`.saboteur/` cache internals are not stable APIs; do not parse them.

## Release posture

The road to 1.0 is a robustness release: no new flags, with the effort going
into the locale matrix, fault-injection coverage and macOS CI. Feature work
lands behind the same contract rules above.

## If the maintainer is unavailable

saboteur is MIT-licensed and the whole development record is public: issues,
pull requests, the review archive under `docs/review/` and this policy. The
governance note in [CONTRIBUTING.md](../CONTRIBUTING.md) covers how a second
maintainer gets oriented; a fork remains possible at any time.
