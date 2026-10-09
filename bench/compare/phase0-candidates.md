# Phase 0: candidate apps, mutant licensing, mutant Rails setup

Collected 2026-10-09 (IST) via `gh api` and public web pages only. Nothing cloned, installed or run.
Legend: [M] = measured from API data; [E] = estimated/inferred (method stated). Data = GitHub API state on 2026-10-09.

## 0. Blocker first: read section 2 before picking an app

mutant's EULA, section 3.1(h), forbids publicly disseminating benchmarks of the software, and 3.1(j) forbids using it to develop a competing product. The brief's goals include a publishable head-to-head and saboteur is a competing tool. Read the quotes in section 2, and get a decision (and legal review if needed) before Phase 1. Picking a candidate app does not depend on that decision.

## 1. Candidate apps

Local machine has Ruby 3.3.4 only. **Every candidate checked needs Ruby >= 3.4** (none still pin 3.3). Expect to install a new Ruby whichever you pick.

Method notes:
- Spec counts: `*_spec.rb` under `spec/` in the recursive git tree at HEAD [M].
- LOC: total bytes of `app/**/*.rb` + `lib/**/*.rb` from tree sizes [M], divided by mean bytes/line from 25 randomly sampled blobs per repo (seed 1) [E].
- Fix commits: the last 200 and the last 800 commits on the default branch [M]. A commit counts when its title (the PR title for merge commits) matches `^(\[?fix|bug|hotfix)` (case-insensitive) and its diff (merge commits: diff against the first parent) touches both `app/` or `lib/` and `spec/`. In merge-commit repos a PR can be counted twice (the merge and its inner commit), so a "unique titles" count is also given. Not every match is a behavioural bug fix (e.g. "Fixes formatting", "Fix CI failures").
- CI runtime: the last 2 successful runs of the test workflow. Times are the "Run tests/rspec" step durations from the jobs API [M].

### Ranked summary

| Rank | Repo | Licence | DB | Ruby | Rails | Spec files | App+lib LOC | CI test step | Fix+spec commits (last 800) |
|---|---|---|---|---|---|---|---|---|---|
| 1 | rubyforgood/human-essentials | MIT | Postgres | 3.4.3 | 8.1.4 | 264 | ~20.1k [E] | ~2.4 min non-system (2 shards) + ~13-18 min system/request (6 shards) | 32 (27 unique) |
| 2 | lobsters/lobsters | BSD-3-Clause (GitHub API shows NOASSERTION) | SQLite (4 DB files) | 4.0.0 | 8.1.3.1 | 109 | ~11.3k [E] | 0.7 min, single job | 23 (23 unique) |
| 3 | huginn/huginn | MIT | Postgres or MySQL | >=3.4.0 (lockfile 4.0.7) | 8.1.4 | 158 | ~23.1k [E] | 1.3-2.3 min per DB/JSON matrix cell | 15 (11 unique), spread over 2022-01..2026-10 |

Also checked and not recommended:
- manyfold3d/manyfold: AGPL-3.0. Needs Redis in CI. Test step takes 9.5-15.9 min [M] (https://github.com/manyfold3d/manyfold/actions/runs/37955748915, https://github.com/manyfold3d/manyfold/actions/runs/37952165051), too slow for mutation runs. The last 200 commits cover only 4 days because of bot noise.
- Freika/dawarich: 1,039 spec files and ~1.9 MB app Ruby [M]. Too big.
- rubyforgood/casa: Ruby 4.0.6, 465 specs, 92 system specs [M]. Larger and system-heavy.
- postalserver/postal: MySQL only.
- alphagov/email-alert-api: 0 matching fix+spec commits in its last 200 [M].
- publify/publify: app code lives in the publify_core gem (9 app .rb files in the repo) [M].
- rubyforgood/abalone: inactive since 2023-07.
- Mastodon: already pinned for another purpose; larger than the mid-size target. Not re-measured here.

### 1. rubyforgood/human-essentials (recommended)

- Repo: https://github.com/rubyforgood/human-essentials, branch `main`, HEAD `d6f829046ee9696499f6781fc8f9e434d270a2be` [M]
- Licence: MIT [M] (GitHub API)
- Ruby: `.ruby-version` 3.4.3 [M]. **Not 3.3.4; install needed.**
- Rails: 8.1.4 (Gemfile.lock) [M]
- DB: Postgres (`pg` 1.6.3). CI uses `postgres:12.3` [M] (https://github.com/rubyforgood/human-essentials/blob/main/.github/workflows/rspec.yml)
- Spec files: 264 [M]. By directory: requests 64, services 56, models 49, system 48, helpers 11, controllers 9, mailers 9, queries 6, jobs 4, other 8.
- App+lib Ruby: 292 files, 566,433 bytes [M]; ~20.1k lines [E] at 28.1 bytes/line.
- CI runtime: `rspec.yml` excludes `spec/system` and `spec/requests` and runs 2 Knapsack Pro shards with a 1.0-1.2 min rspec step each [M] (https://github.com/rubyforgood/human-essentials/actions/runs/37521713452). `rspec-system.yml` runs `spec/system` and `spec/requests` on 6 shards: 1.4-3.6 min per shard, 13.4 min summed [M] (https://github.com/rubyforgood/human-essentials/actions/runs/37521713911); another run was 2.6-3.3 min per shard, 17.4 min summed [M] (https://github.com/rubyforgood/human-essentials/actions/runs/37408202297). Full suite run serially is ~16-20 min of CI-runner time [E], so it may go over the ~15 min budget on a laptop at -j1. Non-system specs alone take ~2.4 min [E, sum of shards].
- Services: Postgres. Background jobs use `delayed_job_active_record`, which is DB-backed; no Redis or Elasticsearch in the Gemfile [M]. System specs need headless Chrome (`cuprite`) [M]. CI uses Knapsack Pro (needs a token); locally plain `bundle exec rspec` should work [E].
- Fix commits [M]: last 200 (2026-07-18..2026-10-01): 17 fix/bug-titled, 9 touching app|lib + spec. Last 800 (2025-07-18..2026-10-01): 97 titled, 32 touching app|lib + spec, 27 unique titles. Examples: `0fed3d1f33` "fix bug where cancellations can take place without a reason", `23841081aa` "Fix lockout from stale session[:current_role]...", `64db0b2fc2` "Bug-5152 Updates storage_location export...".
- Why rank 1:
  - Postgres matches mutant's primary verified Rails recipe (section 3) and the brief's "DB in Docker".
  - Mid-size.
  - The most bug-fix-with-spec commits, so 10-20 real bug-fix commits are easy to find.
  - Fast non-system suite (~2.4 min CI [E]) makes repeated mutation runs affordable.
  - Ruby 3.4 is the smallest jump from the local Ruby 3.3.4.
- Risk:
  - The full suite including system specs is borderline for the 15-min budget [E]. Proposal: mutation subjects in `app/models`, `app/services` and `app/queries`, with system specs excluded for both tools. That needs to be recorded as a deviation.
  - Factory-heavy request specs may be slow per mutant [E].

### 2. lobsters/lobsters

- Repo: https://github.com/lobsters/lobsters, branch `main`, HEAD `07eb114c55501b7101e3d6c092f4eee596703f1f` [M]
- Licence: GitHub reports NOASSERTION. The LICENSE text is a 3-clause BSD-style licence, "Copyright (c) 2012-2019 Created by joshua stein" [M] (https://github.com/lobsters/lobsters/blob/main/LICENSE).
- Ruby: `.ruby-version` 4.0.0 [M]. **Needs Ruby 4.0.** mutant's README lists 4.0 as supported. saboteur's Ruby 4.0 support is not checked here.
- Rails: 8.1.3.1 [M]
- DB: SQLite with 4 test DB files: primary, cache, queue, rack_attack [M] (https://github.com/lobsters/lobsters/blob/main/config/database.yml.sample). [E] mutant's SQLite recipe would need `base_records` extended for the extra DBs; check whether cache, queue and rack_attack are reached through separate abstract classes.
- Spec files: 109 [M]: requests 27, models 26, features 17, extras 9, jobs 7, routing 7, other 16.
- App+lib Ruby: 131 files, 328,305 bytes [M]; ~11.3k lines [E].
- CI runtime: the "Run tests" step (`bundle exec rspec`) takes 0.7 min, 1.2 min for the whole job [M] (https://github.com/lobsters/lobsters/actions/runs/37869681783, https://github.com/lobsters/lobsters/actions/runs/37720085392).
- Services: none beyond SQLite [M, workflow]. 17 feature specs use Capybara [M]. Whether they need a JS driver was not checked.
- Fix commits [M]: last 200 (2026-06-21..2026-10-09): 41 titled, 7 touching app|lib + spec. Last 800 (2025-08-18..2026-10-09): 148 titled, 23 touching app|lib + spec, all unique. Examples: `ed722e4492` "fix story #is_gone? condition", `a9cb71bd09` "fix 500s from ip spoofing", `c1f27cfea2` "fix XSS in link excerpted from comment".
- Why rank 2:
  - Fastest suite by far and no external services, so it is the best for the brief's many repeated runs.
  - Very active, with a steady supply of fix+spec commits.
- Against:
  - Smaller than "mid-size".
  - Needs Ruby 4.0.0, a bigger jump from 3.3.4 and a risk for both tools.
  - The multi-DB SQLite setup needs custom isolation hooks.
  - 125 of 148 fix-titled commits did not touch both app|lib and spec [M]. The tests-with-fixes culture is weaker.

### 3. huginn/huginn

- Repo: https://github.com/huginn/huginn, branch `master`, HEAD `5658f26d4c176e3b6052dc0a6f400f5a45a6ec83` [M]
- Licence: MIT [M]
- Ruby: Gemfile `ruby '>=3.4.0'`; Gemfile.lock `RUBY VERSION ruby 4.0.7` [M]. **Needs Ruby >= 3.4. The lockfile was generated on 4.0.7.**
- Rails: 8.1.4 [M]
- DB: Postgres or MySQL, picked by `DATABASE_ADAPTER`. CI runs both, each with native JSON columns on and off [M] (https://github.com/huginn/huginn/blob/master/.github/workflows/ci.yml).
- Spec files: 158 [M]: models 81 (mostly agents), lib 26, controllers 14, features 9, other 28.
- App+lib Ruby: 182 files, 703,421 bytes [M]; ~23.1k lines [E].
- CI runtime: the "Run tests" step (`bundle exec rake`) takes 1.3-2.3 min per matrix cell [M] (https://github.com/huginn/huginn/actions/runs/37924579415, https://github.com/huginn/huginn/actions/runs/37921683610).
- Services: a DB. No Redis service in the CI workflow [M]. Agents call external HTTP, and the specs are assumed to stub it [E, not verified]. Feature specs use Capybara with Selenium [M, Gemfile].
- Fix commits [M]: last 200 (2026-05-02..2026-10-04): 9 titled, 3 touching app|lib + spec. Last 800 cover 2022-01-13..2026-10-04: 61 titled, 15 touching app|lib + spec, 11 unique. Activity is sparse, so harvesting 10-20 bug-fix commits reaches back years and older Ruby/Rails versions.
- Why rank 3: good size and speed, but the bug-fix history is thin and old, and the Ruby 4.0.7 lockfile is a risk.

### Recommendation

rubyforgood/human-essentials at `d6f829046ee9696499f6781fc8f9e434d270a2be`, on Ruby 3.4.3 and Postgres in Docker. Run the non-system specs (models, services, queries, helpers, controllers, mailers, jobs) for both tools. Measure the full-suite time locally in Phase 0 before deciding whether request specs stay in. Fallback if speed dominates: lobsters, which needs Ruby 4.0.0.

## 2. mutant licensing (public text only; not legal advice)

Sources are pinned to mutant `main` at `d20fb1f789a8485ac11a2d0997ca73ed79583808` [M]. GitHub's licence API reports "Other" [M].

### Usage types

- README: "**Free for open source.** Use `--usage opensource` for public repositories." and "**Commercial use** requires a subscription ($30/month or $250/year per developer)." and "**Enterprise** — reach out directly". https://github.com/mbj/mutant/blob/d20fb1f789a8485ac11a2d0997ca73ed79583808/README.md#licensing
- docs/commercial.md: "**Mutant is free for open source use.**" and "Every organization running mutant on commercial code needs to purchase a subscription per developer." Prices: USD 30/month or USD 250/year per developer (EUR equivalents also listed). https://github.com/mbj/mutant/blob/d20fb1f789a8485ac11a2d0997ca73ed79583808/docs/commercial.md
- The CLI usage values shown in docs are `opensource` (README quick start) and "the commercial usage type" (commercial.md). The docs found do not give the exact string for the commercial value.

### What "opensource" covers (EULA)

LICENSE, 1.2: "Free Project License. If you subscribed under the Free Project License you may use the software for any of your projects that are released under an Open Source License that is hosted on a public source code repository. You are required to keep an up to date list of these repositories in your subscription settings." https://github.com/mbj/mutant/blob/d20fb1f789a8485ac11a2d0997ca73ed79583808/LICENSE

Also from the LICENSE preamble: "In order to use the Software under this Agreement, you must receive a "Source URL" at the time of purchase".

### Clauses directly relevant to this benchmark (LICENSE section 3.1, "You shall not (and shall not allow any third party to)")

- (h): "publicly disseminate performance information or analysis (including, without limitation, benchmarks) from any source relating to the Software;"
- (j): "use the Software to develop a product which is competitive with any Schirp DSO LTD product offerings;"
- (a): "decompile, disassemble, or otherwise reverse engineer the Software or attempt to reconstruct or discover any source code, underlying ideas, algorithms, file formats or programming interfaces of the Software by any means whatsoever"
- 3.2: "UNDER NO CIRCUMSTANCES MAY YOU USE THE SOFTWARE AS PART OF A PRODUCT OR SERVICE THAT PROVIDES SIMILAR FUNCTIONALITY TO THE SOFTWARE ITSELF."
- 7.1: "Schirp DSO LTD may terminate this Agreement immediately upon any breach of Section 3"
- 13.6: governing law is Malta.

### Does a public benchmark by a sponsor of a competing tool fit "opensource" usage? What the text says

- 3.1(h) is a general restriction. Nothing in the text makes it depend on usage type, and the Free Project License (1.2) does not exempt it. **As written, the EULA prohibits publishing benchmarks of mutant, whatever the licence tier.**
- 3.1(j) and 3.2 restrict use "to develop a product which is competitive". Running mutant in order to compare it with saboteur and improve saboteur plausibly falls in that scope. [E: reading of plain text]
- 1.2 covers "your projects" released under an open-source licence. Ambiguous:
  - The target app (e.g. human-essentials) is not the engineer's project.
  - saboteur may be the engineer's or sponsor's project, but the work is a comparison, not mutation testing of saboteur itself.
  - 1.2 also assumes a subscription (a repository list in "subscription settings") and the preamble requires a "Source URL". Whether `--usage opensource` without any sign-up satisfies this is not stated.
- 3.1(a): the clean-room rule prevents source reading. Whether black-box measurement intended to "discover ... underlying ideas, algorithms" counts is ambiguous.
- Smaller inconsistency: 13.2 points to `https://github.com/mbj/mutant/blob/master/LICENSE`, but the default branch is `main` [M].
- Bottom line (not legal advice): the "opensource" usage text does not address benchmarks, and the general restrictions 3.1(h) and 3.1(j) appear to cover this case. Options for the maintainer:
  - Obtain written permission from Schirp DSO LTD (info@schirp-dso.com, the EULA contact).
  - Keep mutant results unpublished.
  - Get legal review.

## 3. mutant's documented Rails setup (public docs)

All quotes are from docs pinned at `d20fb1f789a8485ac11a2d0997ca73ed79583808`.

- **Support:** README: "Mutant runs against Rails applications, including parallel-worker database isolation (PostgreSQL and SQLite)". Verified in its CI on Rails 7.2, 8.0 and 8.1. Ruby 3.2-4.0, Linux and macOS. https://github.com/mbj/mutant/blob/d20fb1f789a8485ac11a2d0997ca73ed79583808/README.md
- **Config file:** one of `.mutant.yml`, `config/mutant.yml` or `mutant.yml` (https://github.com/mbj/mutant/blob/d20fb1f789a8485ac11a2d0997ca73ed79583808/docs/configuration.md). The Rails minimal setup is in `config/mutant.yml` (https://github.com/mbj/mutant/blob/d20fb1f789a8485ac11a2d0997ca73ed79583808/docs/rails.md#minimal-setup):
  ```yml
  requires:
    - ./config/environment
  environment_variables:
    RAILS_ENV: test
  integration:
    name: rspec
  hooks:
    - config/mutant/hooks.rb
  ```
  CLI equivalent: `RAILS_ENV=test bundle exec mutant run -r ./config/environment --integration rspec User`.
- **Integration:** `integration: name: rspec`, gem `mutant-rspec`. The optional `arguments:` list "*OVERWRITES* the hardcoded defaults ... for rspec you *need* to specify the `spec` directory at a minimum". The defaults are `--fail-fast` and `spec`. Extra arguments go through `--integration-argument`. RSpec metadata `mutant: false` excludes a test from killing mutations, and `mutant_expression:` maps a test to subjects explicitly. https://github.com/mbj/mutant/blob/d20fb1f789a8485ac11a2d0997ca73ed79583808/docs/mutant-rspec.md
- **Recommended hooks:**
  - Eager load: `hooks.register(:env_infection_post) { Rails.application.eager_load! }`. The docs say this is "the recommended baseline for any Rails project ... Without it, subject expressions can silently match nothing."
  - Postgres per-worker isolation: each worker gets `CREATE DATABASE <test_db>_mutant_worker_<index> TEMPLATE <test_db>`. Uses the hooks `setup_integration_post` (disconnect the parent), `test_worker_process_start` and `mutation_worker_process_start` ("both registrations are required").
  - SQLite: run `RAILS_ENV=test bin/rails db:test:prepare` first, then copy the DB file per worker into `tmp/mutant/`.
  - Multiple databases: "extend `base_records` with each abstract base class".
  - Also isolate Redis, Sidekiq and file-system state per worker.
  - Verify the setup with `bundle exec mutant test run` first; `mutant environment subject list MyNamespace*` checks that subjects are discovered.
  - Source: https://github.com/mbj/mutant/blob/d20fb1f789a8485ac11a2d0997ca73ed79583808/docs/rails.md
- **Subject selection:**
  - `matcher: subjects:` takes expressions like `Ns`, `Ns*`, `Ns#m`, `Ns.m`, `Ns#`, `Ns.`, `descendants:ApplicationController` and `source:lib/**/*.rb`.
  - `matcher: ignore:` excludes subjects, as does `--ignore-subject` on the CLI. The `# mutant:disable` comment excludes a single method.
  - "If you specify match expressions on the command line they overwrite all expressions in the config file."
  - https://github.com/mbj/mutant/blob/d20fb1f789a8485ac11a2d0997ca73ed79583808/docs/configuration.md
- **Test selection:** `selection: strategy: auto|expression|context_map` (CLI `--selection`, `--selection-path`).
  - `auto` uses simplecov >= 1.2.0 per-test coverage (`track_tests`) in `coverage/coverage.json` when it is present. Otherwise it falls back to `expression`, which takes the prefix of the leading `describe` token.
  - The docs warn: under `expression`, specs that do not name their subject make mutations "report alive even though a test in the suite kills them".
  - [E] This is a fairness-relevant knob. Record which strategy each run "settled on"; the docs say every run prints it.
  - https://github.com/mbj/mutant/blob/d20fb1f789a8485ac11a2d0997ca73ed79583808/docs/test-selection.md
- **Concurrency:**
  - "By default, mutant will test mutations in parallel by running up to one process for each core ... You can control the number of processes created using the `-j/--jobs` argument." (https://github.com/mbj/mutant/blob/d20fb1f789a8485ac11a2d0997ca73ed79583808/docs/concurrency.md)
  - Precedence: `-j/--jobs` > `MUTANT_JOBS` > `jobs:` in YAML > number of processors (configuration.md).
  - "Mutant forks a new process for each mutation".
  - "Do not share one SQLite database file across parallel workers. If you cannot create worker-specific database copies, set `--jobs` to 1."
- **Incremental / diff mode:**
  - `--since <git-ref>`. "A subject is selected by this mechanism when `git diff` reports a hunk that overlaps with the current subjects line range." Example: `mutant --since master 'ProjectNamespace*'`.
  - Limitation: only direct changes select a subject; constant changes and indirect behaviour changes do not.
  - https://github.com/mbj/mutant/blob/d20fb1f789a8485ac11a2d0997ca73ed79583808/docs/incremental.md
- **Other relevant options** (configuration.md):
  - `fail_fast` / `--fail-fast`.
  - `mutation: timeout:` (default: no limit).
  - `mutation: operators: full|light` (default light; the docs say the only difference is `#== -> #eql?`).
  - `coverage_criteria` (`timeout: false`, `process_abort: false`, `test_result: true` by default).
- **Results:** stored in `.mutant/results/` and read back with `mutant session list|show|subject` (README). The schema is in `docs/session-json-schema.yml`, not read here.
- **Documented limitations:** no mutations for methods defined in closures (`class_eval`, `module_eval`, `define_method`, `define_singleton_method`), via string eval, or as singleton methods on non-constant receivers. https://github.com/mbj/mutant/blob/d20fb1f789a8485ac11a2d0997ca73ed79583808/docs/limitations.md
