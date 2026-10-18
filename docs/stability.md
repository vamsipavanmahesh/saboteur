# Stability policy

What adopters can rely on, and how it changes.

## Stable public APIs

### The agent JSON payload (`saboteur run --agent`)

The payload carries an integer `version` (currently `1`) and comes in three
shapes:

| Shape | When | Keys |
| --- | --- | --- |
| Run | The run finished (status `complete` or `partial`) or selected nothing (`not_applicable`) | `version`, `status`, `verdict`, `exitCode`, `provenance`, `counts`, `score`, `scoreDefinition`, `incomplete`, `timeoutCountedAsDetected`, `findings`, `warnings`, `next` |
| Failure | The run never started or could not finish (status `error`) | `version`, `status`, `verdict`, `exitCode`, `message`, `next` |
| Truncated last resort | Even the smallest run payload exceeds the byte budget | `version`, `status`, `verdict`, `exitCode`, `truncated` |

Only `version`, `status`, `verdict` and `exitCode` are guaranteed in every
shape; any other key may be omitted to fit the byte budget, and `truncated:
true` marks the last-resort shape. Consumers must tolerate missing optional
keys and unknown new keys.

`status` is one of `complete`, `partial`, `not_applicable` or `error`.
`verdict` is one of `clean`, `survivors`, `incomplete`, `not_applicable`,
`invalid_invocation` or `tool_failure`.

JSON key order is **not** API: keys are pinned by presence per shape, never
by position, and additive keys may appear in any position.

### The process exit codes

The ordinary CLI and agent mode classify a run the same way but exit
differently:

| Exit | Ordinary CLI | Agent mode (`--agent`) |
| --- | --- | --- |
| 0 | Clean: every selected mutant killed or ignored, or nothing selected at all. Survivors may still be accepted when `--threshold` passes the score, or a budget-stopped run is accepted with `--max-duration-ok` | Verdict `clean` (status `complete`) |
| 1 | Survivors to review: unignored survivors, a missing or below-`--threshold` score, a `--fail-fast` stop, or a failed custom gate | Verdict `survivors` - including a budget-stopped partial run with unignored survivors |
| 2 | Usage or configuration error | Verdict `invalid_invocation` |
| 3 | Incomplete run or tool failure: a stopped run that tested nothing, most mutants errored, an under-threshold incomplete run, or an internal error | Verdict `incomplete` or `not_applicable`, or a `tool_failure` |
| 4 | The `--max-duration` budget stopped the run (unless `--max-duration-ok`) | Never exit 4: exit 1 if unignored survivors are present, otherwise 3 |

Agent mode has no exit 4: budget exhaustion is reported as partial evidence
(the `max_duration` entries in `incomplete[]`), never as its own exit code -
the exit follows the verdict, so a budget-stopped run with unignored
survivors exits 1 and any other budget-stopped run exits 3.
`--max-duration-ok` does not certify an unscored run. Presets that opt out
of budget exits say so in `saboteur help`.

An empty `--since` range is rejected before boot with exit 2 in both modes
(#643). This differs from a non-empty range that selects no subjects.
The modes disagree on an empty selection by design: the ordinary CLI treats
it as clean and exits 0, while agent mode reports status `not_applicable`,
verdict `not_applicable`, exit 3, so a harness never mistakes "nothing was
selected" for "everything passed".

### The machine report (`.saboteur/report.json`)

The [Stryker mutation-testing-report schema](https://mutationtesting.io/schema/mutation-testing-report-schema.json),
which is versioned upstream.

Contract specs (`spec/saboteur/reporter/agent_contract_spec.rb`) fail when a
pinned key, a `status` or `verdict` value, the version or an exit code
moves.

### The dry-run inventory (`saboteur run --dry-run --format json`)

The planned mutation set as one JSON document, described in
[dry-run-json.md](dry-run-json.md). It carries an integer `schema_version`
(currently `1`); consumers must ignore keys they do not know, and key order
is not API. Only a breaking change raises the number.

## How they change

Each surface is governed by its own version:

- **The agent payload** is governed by its integer `version`. *Additive*
  changes (a new payload key alongside the existing ones, a new `incomplete`
  reason code) ship in a normal release with a CHANGELOG entry; the new key
  may appear one release before the old one is removed. *Breaking* changes
  (a renamed or removed key, a changed `status` or `verdict` value) require
  a bump of `version` and a CHANGELOG entry under a `Changed` heading.
- **The process exit codes** are a process-level contract, not covered by
  the payload `version`. A remapped or removed exit code is a breaking
  change announced under a `Changed` heading in the release that makes it;
  there is no overlap period where one invocation can emit both the old and
  the new code.
- **The machine report** follows the upstream Stryker schema versioning.
- **The dry-run inventory** is governed by its integer `schema_version`,
  under the same additive-versus-breaking rules as the agent payload.

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
