# Benchmark brief: saboteur vs mutant on an open-source Rails app

(From the maintainer, 2026-10-09. Kept verbatim in intent; see docs/status.md
for progress.)

Goal: a fair, reproducible, publishable head-to-head comparison on the same
Rails app at the same commit. The goal is the truth, not a win: report every
metric where mutant wins.

Hard rules:
- Clean room: run mutant only as a black box through its CLI. Its public docs
  may be read to configure it; its source code and specs may not be read,
  opened or grepped, including the installed gem's files.
- saboteur is frozen at SABOTEUR_REF for the whole run; bugs found are logged.
- Configure mutant as its docs recommend for Rails; failures are reported as
  mutant results, never dropped silently.
- Same machine, Ruby, app commit, test command and concurrency for both;
  record hardware, OS, Ruby and gem versions.
- Test env only, DB in Docker, no network from tests, never read secrets.
- One script, bench/compare/run_all, regenerates every number.

Phases (stop at each STOP):
0. Suggest 3 candidate apps (RSpec, Postgres or SQLite, suite under ~15 min,
   active history with bug-fix commits that add tests); after the pick, pin
   the commit, get the suite green, find flaky tests (3 runs), exclude them.
   STOP.
1. Install and configure both; record config lines, setup steps, setup time,
   workarounds. Pick overlapping subjects in 3-5 directories; record what
   each tool cannot handle. STOP.
2. Measurements, 3 runs each at concurrency 1 and N:
   correctness (false kills on up to 300 kills, flaky survivors,
   repeatability, leftovers); speed (full, per mutant, first survivor, diff
   mode on 10 real commits); resources (peak memory, CPU, CI cost from
   current GitHub Actions pricing, cited); usefulness (blinded: 50 random
   survivors per tool labelled by a separate reviewer agent, then 20 given
   to the maintainer to check - STOP); real bug detection (10-20 bug-fix
   commits, diff mode on the old code with old tests); Ruby coverage by
   construct; ease of use.

Output: bench/compare/REPORT.md (summary table saboteur | mutant | winner,
a section per metric, every case where mutant won, limitations),
bench/compare/raw/*.json, bench/compare/run_all. Measured vs estimated
stated. Stop after 2 hours if either tool cannot produce results.
