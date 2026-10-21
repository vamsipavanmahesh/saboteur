# Preflight

`script/preflight` (run it as `ruby script/preflight`; the file does not need the executable bit) is a local check you run on one exact base and head before you ask for review. It
finds the cheap, repeat mistakes first: protected files, sign-off, SPDX headers, whitespace, lint and
specs. It is not CI, not a review and not an approval. A contributor can edit it, so the existing CI,
DCO check and panel gate stay the authority.

## Run it

```sh
ruby script/preflight --base <40-char main sha> --head <40-char head sha> --base-ref main --mode fast
ruby script/preflight --base <40-char main sha> --head <40-char head sha> --base-ref main --mode full
```

- Both SHAs must be full, lowercase, and present locally. `HEAD` must equal `--head` and the tree must be
  clean. Branch names are refused.
- `--base-ref` must be `main`. A deliberate stack is not something this tool can call main-ready.
- It never fetches, installs gems, rebases, commits, pushes or comments. It makes no network call itself, but the
  specs it runs may.
- Output always goes to `tmp/preflight/<run-id>/` (not configurable): `report.json`, `report.md`, one log file per
  command and the raw RSpec JSON. Nothing from an earlier run is reused. `tmp/preflight` must be a real directory
  inside the checkout with no tracked files, and files marked assume-unchanged or skip-worktree are refused,
  because both would hide edits from the clean-tree check.

## Result

| exit | verdict | meaning |
| --- | --- | --- |
| 0 | `automatic_checks_passed` | Full mode, every required check passed. Not approval. |
| 0 | `partial` | Fast mode, or full mode with a check that did not run or a `review_required` notice. Not a pass. |
| 1 | `failed` | A check found a problem. |
| 2 | (no report) | Invalid arguments, or a checkout whose identity cannot be verified (bad SHA, dirty tree). |
| 3 | `incomplete` | A check could not finish: missing tool, timeout, malformed output, inputs changed during the run, an unreadable or malformed document, or an output directory that cannot be created (then no report exists, only a message on stderr). Changed inputs and any evidence gap (an incomplete check, a missing identity) outrank `failed`; the findings stay in the report. |

The report lists the manual obligations that no script checks. Read them.

## Checks, in order

1. Identity: exact SHAs, clean tree, merge base, change inventory (NUL-delimited, renames shown as a delete
   plus an add, symlink and submodule changes flagged). An empty change set fails.
2. `protected_paths`: protected list read from `script/panel-gate/policy.json` **at the merge base**, plus the
   active `config/saboteur*.rb` files the policy does not list yet. Any change fails. There is no override flag.
3. `check_policy_changes`: changes to `.rubocop.yml`, Gemfile and gemspec, `.rspec`, `config/`, the harness
   and its specs. These define how checks judge code, so a green run after such a change is not comparable.
   Review the diff. GitHub does not protect all of these files; the report says "review required", not "protected".
4. `dco_signoff`: every non-merge commit has a `Signed-off-by: <author>` trailer (`git interpret-trailers` block, so a sign-off embedded in the subject or mid-body does not count). A `Co-authored-by` trailer whose
   whole name is a known AI tool or bot (or whose address is a known AI vendor or `[bot]` address), or a
   `Generated with/by <tool>` line, fails. A human co-author, even one named "Claude Martin", passes. The list
   is a heuristic and misses tools it does not know.
4a. `base_snapshot` and `docs_update`: `--base` is compared with the local `origin/main` (a difference is
   `review_required`; no origin/main is `not_applicable`). CLI files changed without a `docs/` change is
   `review_required`. Neither proves freshness or that the docs text is right.
5. `spdx_headers`: files this change touches, same file set and fixture exemption as CI.
6. `diff_check`: `git diff --check`.
7. `rubocop`: full `bundle exec rubocop` with the repository's `.rubocop.yml`. The JSON report is parsed strictly
   (no duplicate keys, the required fields present with the right types, non-negative counts that match the file and offense lists, at least one file
   inspected) and must agree with the exit status.
8. `harness_specs`: `bundle exec rspec spec/script/preflight`. The RSpec JSON is parsed strictly: counts match the
   example list, every status is known, no load errors, zero examples never passes.
9. Full mode only: `full_suite` (`bundle exec rspec`).
10. Cheap checks all run. The costly ones run in order and stop at the first that fails or is incomplete; later
    ones are recorded as `not_run`.
11. Before and after the run it fingerprints the inputs, in two parts. Passive part (files and git only, taken
    before any check): the content of every tracked file on disk, the ignored inputs that change execution
    (`Gemfile.lock`, `.bundle/config`, `.rspec-local`, `.rubocop-local.yml`), the Ruby and RubyGems versions, the
    `ruby` and `bundle` executables found on `PATH` the way the OS finds them (readable executable file; an empty
    or relative `PATH` entry is refused), the effective Gemfile (`BUNDLE_GEMFILE`, relative to the checkout) and
    its lockfile, the app and user Bundler config (digests only, never contents), and a fixed list of environment
    variables. Dependency preparation: when the ignored `Gemfile.lock` is missing (a fresh checkout), `bundle lock --local` creates it from locally installed gems, with no network. The "before" fingerprint is taken after that step, and the only difference accepted from the one before it is a lockfile that did not exist and now does. Any other difference (tree, tracked file, another input) is a gap. So a first run in a fresh checkout needs no rerun, provided the gems are installed. Dependency part: the Bundler version and the `bundle list` result, which is read-only in the harness's own orchestration (it never runs a lock command). That is not a sandbox guarantee: the candidate's Gemfile or Bundler could still write files, and the before/after comparison is what catches that. It evaluates the candidate's
    Gemfile, so it runs only after the cheap checks, including `protected_paths`, did not fail. If a cheap check
    failed it is not run, and no costly check runs either. A difference in either part is `incomplete`.
    A tracked symlink is bound to the content it resolves to; one that leaves the checkout, a directory or a
    submodule stops the run. A Bundler or ignored input that exists but is not a readable regular file (directory,
    broken symlink, unreadable) also stops the run and is never treated as absent. `bundle list` is names and
    versions only, not gem source contents. Not covered: other `BUNDLE_*` and environment variables, the clock,
    the network, the operating system and shared libraries.
    Every fingerprint and report read opens the file once without blocking and requires the opened descriptor to
    be a regular file, so a FIFO swapped in after a check ends the run as `incomplete` instead of hanging. The
    lockfile follows Bundler's rule (`gems.rb` to `gems.locked`, any other name plus `.lock`). Size cap: a file over 50 MB (a tracked fixture, a
    Bundler file, or a `ruby`/`bundle` executable on `PATH`) is an `incomplete` gap, not a pass. Limit: a symlink
    retargeted between the resolve and the open changes only content, which the before/after comparison catches.
12. Output safety: `tmp` and `tmp/preflight` must be real directories inside the checkout, verified with
    read-only git calls before anything is created. Candidate code (a Gemfile, a spec, a tool) runs while the output
    directory is open, so every write goes through one routine that re-checks the directory chain from the checkout
    root (real directories, owned by you, not world-writable) and creates the file with `O_EXCL | O_NOFOLLOW |
    O_NONBLOCK`: it must be new, cannot be a link, and a FIFO cannot make it block. RSpec does not write its JSON to
    a path in the checkout: it writes to a pipe (file descriptor 3) that only the harness reads, so a spec cannot
    redirect that write. Before the report is written, every entry under the run directory must still be a directory
    or a regular file (a bounded walk: at most 16 levels, 5000 entries and 20 s, otherwise it is not complete), or the
    run is `incomplete` (check `output_safety`); a failed write after that is `report_output`. Limits: Ruby has no
    `openat`, so a directory swapped for a link between the chain check and the open is narrowed, not excluded, and a
    swap that is undone before the end of the run cannot be detected. The tree check only catches a bad state that is
    still there when it runs. The tool does not claim the output directory is tamper-proof against code running as the same user.

The report also records the local `origin/main` snapshot (freshness unverified), a SHA-256 of the base policy file,
the mode and blob of every changed file, every command run with its logs and hashes, and the exact rerun command.

## What it does not do yet

These rows are `not_implemented` and show as `not_run` in full mode, so full mode cannot report
`automatic_checks_passed` yet:

- changed-method dogfood (`saboteur run --since`), whole-source dogfood for operator changes
- registry/TIERS bidirectional contract and emitted-ID checks
- claim ledger and default versus opt-in proof (manual)
- live PR base, CI and gate state (needs live GitHub, outside this tool)

## Finding classes: what is covered

"Fixture" means a negative spec plus a valid control exist in `spec/script/preflight/`. A passing spec count
is not proof of coverage; read the spec.

| Finding class | Status | Scope and limit |
| --- | --- | --- |
| Lint found late | automatic, fixture-backed | Full configured RuboCop. Real-RuboCop spec uses a line-limit violation and a clean file. The class-length limit is covered by the same real run, not by its own fixture. Design is not judged. |
| DCO and SPDX | automatic, fixture-backed | Git metadata only. SPDX covers touched files, not the whole tree. |
| Protected edits | automatic, fixture-backed | Exact and descendant paths, deletes, moves, symlinks, base-policy source. Cannot grant approval and does not replace the remote gate. Policy gap for `config/saboteur*.rb` is reported locally; fixing the remote policy is a separate maintainer change. |
| Check-policy edits | automatic, fixture-backed | Detects and flags; a human judges whether the change is legitimate. |
| Stale or short SHAs, changed inputs | automatic, fixture-backed | Full SHAs required; tree and ignored-input digests compared. Self-reported evidence is still untrusted by reviewers. |
| Swallowed or malformed tool output | automatic, fixture-backed | RuboCop and RSpec reports validated against exit status, timeouts, truncation and signals. Not yet applied to saboteur's own JSON reports (dogfood is not implemented). |
| Stacked PR / wrong base | partial | `--base-ref main` required. Live PR base needs a GitHub check by the lane or reviewer. |
| Claims stronger than code | manual | Listed in the report. No script proves a claim. |
| Fail-open on malformed input in product code | manual | Product specs must cover each input. The harness only does this for its own parsers. |
| Default versus opt-in | manual | Needs a CLI fixture in the product specs. |
| Own-source survivors, registry/TIERS, descendant guards | not_implemented | Planned: dogfood and contract checks. |
| Runtime or speed claims | manual | Needs the paired AB/BA evidence in AGENTS.md. |

## Limits

- A process group is not a sandbox. Specs and tools the harness runs can detach children or use the network.
- Every command runs in its own process group. After it ends (or times out) the group gets TERM, a grace period,
  then KILL. Leftover processes, a pipe still held open, signal deaths, invalid UTF-8 and output over 20 MB each make
  the result unusable (`incomplete`), never a pass. A grandchild that moves to a new process group escapes the cleanup.

## Measured cost

Indicative numbers, not a benchmark. Sequential runs per row (three each, except by-hand fast, where two are kept, see below), median (range) in seconds, taken on the code of
the slice 1 PR before its last docs-only change. Environment: 2 vCPU Intel Xeon 2.6 GHz, Linux 6.1, Ruby 3.3.0,
Bundler 2.5.3, CPU shared with other jobs. Full mode got slower than my first measurement (about 307 s) because
`main` gained specs and the machine was busier, so compare rows within one table only.

| scenario | what runs | median | range | verdict |
| --- | --- | --- | --- | --- |
| preflight, fast | `ruby script/preflight ... --mode fast` | 30.3 | 29.9 to 30.8 | partial |
| by hand, fast | `bundle exec rubocop && bundle exec rspec spec/script/preflight` | 29.1 | 28.5 to 29.7 | n/a |
| preflight, full | `ruby script/preflight ... --mode full` | 405.9 | 402.7 to 407.2 | partial |
| by hand, full | `bundle exec rubocop && bundle exec rspec` | 361.2 | 360.7 to 372.6 | n/a |

Raw runs (ms): preflight fast 30754, 30326, 29943. By hand fast 29695, 28472, plus one run of 782364 that overlapped an
idle pause of the sandbox, so it is dropped, leaving two by-hand fast runs. Preflight full 402696, 407246, 405890. By hand full 361226, 360735, 372585.

What this says: running the checks through preflight costs about 1 s more in fast mode and about 45 s more in full mode
than typing the commands in the table. In full mode part of that is not overhead of the harness itself: preflight runs
`harness_specs` (about 18 s) and then the full suite, which runs those specs again, while the by-hand full command runs
the suite once. The rest is the extra cheap checks, the fingerprint before and after, and the report. It does not make the checks faster. What it saves is the wasted cycle: a protected-file edit
fails in about 0.3 s and a RuboCop offense in about 2.5 s (measured earlier, five runs each), and the costly checks are
skipped, so a reviewer round trip for a problem it catches is avoided. The extra time in full mode also buys a run that
is checked for changes underneath it.
