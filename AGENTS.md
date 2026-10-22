# Working agreements

Rules for anyone changing this repository, human or automated.

## Licensing

- Never copy from, read, or consult the `mutant` gem (the commercial Ruby mutation testing library). It is commercially licensed. Keep all code, docs and site content independent of it.
- `mutineer` (davidteren/mutineer, MIT) is the allowed benchmark reference.

## Scope

- saboteur is RSpec-only on purpose. Do not add Minitest support. See "Not planned" in [ROADMAP.md](ROADMAP.md).

## Commits

- Every commit carries a DCO `Signed-off-by:` trailer that exactly matches the commit's git author (name and email). `script/check-dco` enforces this.
- Do not add AI assistant attribution (such as `Co-Authored-By`) to commits or pull requests unless the maintainer asks.

## Quality bar

- Principal-engineer level: SOLID, design patterns where they help, tests first (TDD), scalable design.
- Write comments and names in simple English. Comments must be technically precise. Do not claim more than the code does.

## Naming

Names follow Uncle Bob's Clean Code conventions:

- Intention-revealing, pronounceable and searchable.
- No abbreviations and no noise words (`Manager`, `Data`, `Info`, `Util`).
- Classes and modules are nouns. Methods are verbs.
- A name says what the thing does, so no comment is needed to explain it.

## Documentation

- A pull request that changes CLI flags, behavior or usage must update the reference docs under [docs/](docs/) in the same pull request; README.md stays short and is not the CLI reference.
- A pull request without that docs update fails review.

## Review

- Keep a pull request small: at most about 300 changed lines (added plus removed) of code, specs and docs together. CHANGELOG lines and ignore-list entries do not count. A fix and its tests stay in one pull request; split bigger work by behavior, never by file type. Small pull requests keep dogfood and panel reviews fast, and a bad one is easy to undo.
- A pull request opens with the first push. Open it as a draft while the work is in progress. No branch sits on origin without a pull request.
- Adversarial panel reviewers analyze the open pull request in parallel. Each reviewer posts their review as a comment on it as soon as their analysis is done, independently of the others.
- The author starts resolving each comment as soon as it is posted, without waiting for the rest of the panel. Fixes land as new commits, then the panel re-reviews.
- Merge only when the panel and the author agree and CI is green.
- Exception: a docs-only change (Markdown files and `docs/` only, no code, specs, scripts or workflows) may be pushed straight to `main` without a pull request, CI or panel once an independent reviewer has approved the exact diff. It still carries the DCO sign-off.

## Preflight

- Before asking for review, run `ruby script/preflight --base <full main sha> --head <full head sha> --base-ref main --mode fast` on the exact head, plus the specs the change touches and the changed-method dogfood (`bundle exec exe/saboteur run --since origin/main`). The full suite runs in CI; `--mode full` runs it locally when CI is not available. See [docs/preflight.md](docs/preflight.md).
- A green preflight is not approval and does not replace the panel, CI or the live check of the PR base.
- Fast mode is partial. Any new push needs a fresh run.

## Performance claims

A claim about speed or memory needs reproducible proof in the pull request:

- Paired before/after runs, ordered AB then BA, at least 5 pairs.
- Identical worker counts and workloads on both sides.
- Physical memory metrics: PSS (from `smaps_rollup`) or cgroup memory. Never use summed RSS as a memory claim.
- No single-run numbers.
- Verdict parity checked per mutant: the change must not alter any mutant's result.
- Include the commands and raw data so the maintainer can rerun them.
