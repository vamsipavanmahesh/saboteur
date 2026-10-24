# Solidus replay recipe (prepared; saboteur commands pending verified 0.13.0 SHA + its docs)

1. Worktrees: ~/field/solidus/trees/pr<N>-{base,head} (created by field/pr-tree-checks.sh; base/head SHAs in selection.csv).
2. Per-PR scoped green check runs FIRST (kind=baseline measurements under reports/pr<N>-{base,head}-scope/); red in scope blocks/annotates that PR's replay with actual per-tree evidence, never inference.
3. saboteur install + docs/ci-whole-suite-map.md EXACTLY as written (step 3); any failure = finding, reported as-is, no silent excludes.
4. saboteur pr per selection.csv: base=parent, head=merge; record mutants/killed/survived/timeouts/errors/score/wall/exit + keep reports/<scenario>/report.json untouched.
5. Parallelism: rerun one PR replay with --jobs N (per-worker DBs); compare every mutant verdict vs serial.
6. Determinism: rerun one PR replay twice; diff ids/statuses/killedBy/gap; report diff even if empty.
7. No survivor/kill triage by this agent; raw reports go to main for the fresh-context triager (seed 20261023 selection).
