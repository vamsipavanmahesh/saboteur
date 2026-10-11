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

- A pull request that changes CLI flags, behavior or usage must update [README.md](README.md) in the same pull request.
- A pull request without that README update fails review.

## Review

- A pull request opens with the first push. Open it as a draft while the work is in progress. No branch sits on origin without a pull request.
- The adversarial review panel posts its review as comments on the open pull request.
- The author resolves those comments with fixes as new commits, then the panel re-reviews.
- Merge only when the panel and the author agree and CI is green.

## Performance claims

A claim about speed or memory needs reproducible proof in the pull request:

- Paired before/after runs, ordered AB then BA, at least 5 pairs.
- Identical worker counts and workloads on both sides.
- Physical memory metrics: PSS (from `smaps_rollup`) or cgroup memory. Never use summed RSS as a memory claim.
- No single-run numbers.
- Verdict parity checked per mutant: the change must not alter any mutant's result.
- Include the commands and raw data so the maintainer can rerun them.
