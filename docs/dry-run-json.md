# The dry-run JSON inventory

`saboteur run --dry-run --format json` prints the planned mutation set as one
JSON document on stdout and exits 0. It reads source only: the app never
boots and no test runs. Without `--format json`, `--dry-run` keeps its
human-readable text output.

The plan excludes subjects known from source to be unsupported, such as
methods defined inside blocks, and names them in warnings. It cannot know
coverage-dependent skips without loading the app and tests, so a real run
may execute fewer mutants than this static plan.

Two guards keep the surfaces unambiguous: `--dry-run --agent` refuses and
names `--format json` as the replacement, and `--format json` without
`--dry-run` is a usage error (exit 2) pointing at `--format agent` for run
summaries.

## The document

Top-level keys:

| Key | Meaning |
| --- | --- |
| `schema_version` | Integer version of this document, currently `1`. Consumers must ignore keys they do not know; only a breaking change raises the number. |
| `saboteur_version` | The saboteur release that produced the document. |
| `mode` | Always `"dry-run"`. |
| `operators` | The effective operator names for the run. |
| `test_selection` | The test-selection strategy (`auto`, `all`, ...). |
| `tests` | The explicit `--test` list; empty when none was given. |
| `subjects` | One entry per subject: `id`, `file`, `start_line`, `end_line` and its planned `mutants` count. |
| `mutants` | Every planned mutant (see below). |
| `skipped` | Candidates excluded from the plan, each with its `reason` (see below). |
| `totals` | `mutants`, `dropped_by_max_mutants_per_method` and `incomplete_files` (files whose source discovery failed). |
| `estimated_seconds` | The estimate from the cached coverage map; `null` when no estimate exists (no cached map or incomplete discovery). |
| `warnings` | Diagnostic warnings from planning; text mode prints them as `warning:` lines. |

Each `mutants` entry names one planned mutant:

- `digest` - the stable 16-hex-character id a run or `saboteur run --id`
  replay computes for the same mutant.
- `subject`, `operator`, `file` and `line` (the 1-based line of the first
  edit).
- `edits` - every edit as `start_byte`/`end_byte` offsets into the file as
  read from disk, with the `original` and `replacement` text, so each edit
  is self-contained.

Each `skipped` entry carries a `reason`:

- `max_mutants_per_method` - planned but over the per-method cap; the entry
  is a full mutant entry like those in `mutants`.
- `inline_suppression: <directive reason>` - suppressed by a
  `saboteur:disable-line` directive; the entry carries `digest`, `subject`,
  `operator`, `file` and `line`.
- `hazardous` - refused by the hazard guard; the entry names only
  `subject`, `operator` and `file`.

Inline suppressions and hazard refusals are recorded during candidate
filtering, before diff restriction and the per-method cap - the same scope
the text-mode audit names.

## Stability

The inventory is a stable public API under the
[stability policy](stability.md): additive keys may appear in any release,
and only a breaking change raises `schema_version`. JSON key order is not
API.
