# Project status, decisions and checklist

Single source of truth for long-running work on saboteur. Update it in the
same commit as the work it describes. Newest entries at the top of each log.

Last updated: 2026-10-09 (IST).

## How to resume

```sh
cd saboteur
git log --oneline | head -20          # what landed
bundle exec rspec && bundle exec rubocop
```

Then read "Next up" below. Heavy runs (dogfood, pinned targets, Rails app)
go through the watchdog, one at a time (see "Safety rules").

## Working rules (from the maintainer)

- Naming in the Uncle Bob sense: names reveal intent; classes are nouns,
  methods are verbs; no noise words (Manager, Data, Info), no abbreviations;
  a query does not hide a command, and when it must, its comment says so.
- TDD: a failing spec first for every new behaviour, then the code. For a
  bug, first a spec that reproduces it (and check it fails without the fix).
- Comments in simple English: short sentences, common words, one idea each.
  Say why, not what.
- Think as a principal engineer: layering, boundaries, the public API, and
  what the next phase needs.

## Phases (from the original brief)

| phase | scope | status |
|---|---|---|
| 0 | name check, scaffold, licensing, CI skeleton | done (name: saboteur; `tamper` taken on rubygems) |
| 1 | core engine on fixtures, 4 required tests | done |
| 2 | two pinned public gems, survivor classification | done: docs/validation/phase-2-gems.md (numbers predate line-level selection; re-measure) |
| 3 | --since, Stryker JSON, ignore list, exit codes, config (minitest dropped by scope decision) | done |
| 4 | Rails integration on a large public app | in progress on rubyforgood/human-essentials d6f8290 (Mastodon dropped: human-essentials chosen in bench Phase 0); docs/validation/phase-4-rails.md |
| 5 | parallel workers, own DB each | built (--jobs N); gems measured; Rails per-worker DBs built, being validated on human-essentials |

## Next up (ordered)

- [ ] Benchmark (bench/compare/BRIEF.md): Phase 0 done (bench/compare/phase0-candidates.md); pick:
      rubyforgood/human-essentials at d6f8290 (MIT, Postgres, needs Ruby 3.4). Saboteur-only
      measurements until mutant licence question is resolved.

- [ ] Fiddle: declare it (stops being a default gem in Ruby 3.5)
- [ ] Architecture steps E and F (typed config schema, public API docs)
- [ ] Triage dogfood survivors (215 live at b9c4068 incl. new engine parts). Done: Diff, terminal reporter, scheduler, operators (0 live; equivalents in .saboteur-ignore.yml). Next: recorder.rb (17), cli.rb (14), subject.rb, git_diff.rb, ...
- [ ] Docs: recipes (Sidekiq, WebMock, VCR); README, design.md and CHANGELOG refreshed 2026-10-09
- [x] Phase 4: human-essentials full scope at --jobs 6: 4,080 mutants, 3,510 killed, 452
      survived, 1 timeout, 0 errors, 3,602 s (docs/validation/phase-4-rails.md)
- [ ] Phase 4: classify 30+ of the 452 survivors; census of defs inside blocks
- [ ] Survey items that need no spec change: survivor ranking, HTML report, pseudo-tested label

## Open questions for the maintainer (do not decide alone)

- Benchmark vs mutant is BLOCKED by mutant's licence (verified in its
  LICENSE, section 3.1): (h) no public dissemination of performance
  information or benchmarks; (j) no use of the software to develop a
  competing product; (a) no attempt to discover its underlying ideas or
  algorithms. Decision: mutant is not installed or run. Options for the
  maintainer: written permission from Schirp DSO LTD (info@schirp-dso.com)
  waiving 3.1(h) and (j); or benchmark saboteur alone on the brief's metrics
  (in progress, so the mutant column can be added if permission comes); or
  legal review. Not legal advice.

1. Publishing: name `saboteur` free on rubygems and as glomopay/saboteur on
   GitHub as of 2026-10-09; the maintainer publishes, not the agent.

## Claude-Grok review loop (docs/review/)

Round 4 (2026-10-09): Grok "AGREED" on A1-A10 and the result cache; no new
defects of substance; its remaining edge cases fixed in the same session.
Scores (Grok): Ruby mutation testing 7/10 with the M2 operator change, else
6/10; signal-to-noise 7/10 with M2+M3, else 6/10; resource efficiency 6/10.
Its bar for "state of the art": M1 nesting default, M2 before/after table on
the pinned gems, crash-kill share per operator, cache demo incl. an edited
killer file; for apps, Mastodon at the pin under the watchdog with 30+
survivors classified and a census of defs inside blocks.

## Decisions log

- 2026-10-10 Child logs live in .saboteur/logs (cleared each run) instead of
  a new $TMPDIR/saboteur-* per run (1,711 had piled up). SimpleCov is turned
  off through Object.const_added the moment the app defines it, instead of
  saboteur requiring simplecov (which ran the app's .simplecov first).

- 2026-10-10 Parallel Rails runs fixed (human-essentials, --jobs 3, Item:
  verdicts identical to --jobs 1, 142 s vs 263 s). Five defects, each
  found from evidence, not guessed:
  1. Workers died silently: a crashed worker now sends its exception as
     its last line, the item's error says why (or which signal), and the
     pool stops after 3 workers die before their first item.
  2. Rails 8 has no PoolConfig#connection_class: owner_of reads the
     connection descriptor (7.2+) or the class (7.1).
  3. libpq's GSSAPI probe segfaults forked processes on macOS (crash report:
     krb5 -> xpc_connection_resume): rails mode sets PGGSSENCMODE=disable
     unless set (databases are local only).
  4. Copying the test database left ActiveRecord::Base on the "postgres"
     maintenance database in every worker; copies now go through
     saboteur's own MaintenanceRecord class. Re-pointing now covers every
     role and shard (connects_to reading: pools stayed on the shared DB).
  5. macOS over-counts RLIMIT_CPU for processes with many waking threads
     (reproduced: SIGXCPU at 5.4 s of a 20 s limit with 20 threads waking
     every 10 ms). The child now checks SIGXCPU against its real CPU time,
     ignores early ones, and the hard limit is 20x the budget.
  Kills now carry the killing test's failure message; an overturned kill
  says why the test failed with the method unchanged (that is how defect 4
  was found: PG::UndefinedTable).

- 2026-10-10 Neutral check replaced by a verdict check (design.md section 8).
  Reason, measured on human-essentials `--subject Item`: two callbacks that
  every factory runs have ~850 covering tests each, and the per-subject
  neutral checks cost 286 s against 211 s for all 98 mutants. Now: kills are
  confirmed after the fact by re-running each kill's exact test sequence up
  to the killer with the method unchanged (stricter than before: it checks
  the order each kill really ran in); timeouts come from recorded per-test
  durations and are calibrated on the spot against a real unchanged run.
  Result: identical verdicts on all 98 Item mutants, dry-inflector and
  tty-color snapshots; Item 494 s -> 263 s. A first version without
  calibration produced one false timeout (caught as an error, not reported
  as a timeout), which is why calibration exists.
  Grok review not obtained: its headless mode (-p) stopped after its first
  turn three times (plan mode, --no-subagents, --max-turns 80 all tried).
  Own adversarial pass recorded in the commit message.
- 2026-10-10 Coverage-map child output goes to .saboteur/coverage-build.log,
  and a child that dies before reporting says how (exit status or signal).
  The first human-essentials run died that way once, 5 s in, cause unknown
  (it did not happen again); before this change the reason was lost.
- 2026-10-10 --subject warns about a pattern that matches nothing (patterns
  are names, not globs).

- 2026-10-10 Review round 5 fixes: workers in their own process group, a
  liveness check every second (a dead worker whose stray child holds its
  pipe no longer hangs the parent), supervised children close the worker's
  pipes, workers forget the parent's live trees, broken pipes requeue the
  item, unreadable results become errors; Rails re-points every pool and
  names copies app_test_saboteurN (never a parallel_tests name); SQLite
  copies include -wal/-shm. Disagreed with Grok on putting jobs in the
  verdict fingerprint: verdicts are independent of jobs by design (verified
  identical on all 267 dry-inflector mutants), and keying on jobs would
  make the cache useless across modes.

- 2026-10-09 Parallel workers (Phase 5, gems): --jobs N forks N workers from
  the booted parent; each runs whole subjects through the Scheduler and
  returns plain data. dry-inflector: 24.99 s -> 7.24 s at 14 jobs (3.45x),
  identical verdicts on 267 mutants, peak 30 processes / 1.1 GB, no
  leftovers. Limit: one large subject runs on one worker (Amdahl); next
  step is splitting large subjects. Rails needs one database per worker
  (TEST_ENV_NUMBER is set per worker; reconnect is Phase 4 work).

- 2026-10-09 Phase 5 (parallel workers): the benchmark brief requires runs
  at concurrency N for both tools and the maintainer said not to pause, so
  parallel workers will be built after benchmark Phase 0 (logged decision;
  maintainer may veto).
- 2026-10-09 Dogfood triage of the operator code: 36 survivors -> 0 live.
  Most survivors exposed redundant guards (checks already done by `add`'s
  same-text rule or by the nil-safe walker); those were removed rather than
  tested. prism requirement raised to >= 1.2 to drop compatibility branches.

- 2026-10-09 M2 adopted after measurement (docs/validation/phase-2-gems.md):
  sufficient ROR/COR sets and predicate true/false coarse mutants. tty-color
  gained 4 real gaps and no noise; dry-inflector survivors unchanged.
  Mutant licence decision for the benchmark: maintainer said not to pause;
  will read mutant's public licence terms (docs only) before installing and
  record the basis here.

- 2026-10-09 Maintainer decisions: M1 default reeval = nesting (done);
  M2 adopt the research operator changes with a before/after measurement;
  M3 keep all `||=` mutants; M4 resource-limit stops get their own status,
  out of the score.

- 2026-10-09 Opt-in result cache (--incremental), review gap 5: verdicts
  reused while method, mutant, covering tests and their files, lockfile,
  verdict config and version are unchanged; fully reusable methods fork
  nothing. Callee changes are a documented hole.

- 2026-10-09 Review round 1+2 items A1-A10 done: coarse rules (rescue,
  arid), cache key inputs, baseline timeout reason, alias re-pointing with
  source-location guard, libproc hardening, quoted git paths, assertion vs
  crash kills, review-shaped --since (fine mutants on changed lines only,
  one survivor per line in the terminal).

- 2026-10-09 Maintainer: drop Minitest support to reduce scope; RSpec only.
  Adapter, fixture, dev dependency and the `test_files` config key removed;
  `Integration::Base` stays public.
- 2026-10-09 Claude-Grok review loop started (docs/review/). Round 1 fixes
  done: no body_raise where the method's rescue catches it (it stopped all
  fine mutants); body_nil kept when only the last line is arid; coverage
  cache key includes spec support files, .rspec and boot files.

- 2026-10-09 Mutant children name themselves in the process title
  ("saboteur: Klass#meth operator"); script/watchdog writes the killed tree
  on trip. That pinned the second trip to one mutant: removing the
  recursion guard in Engine#call made the guard's own spec start a real
  run. Fixes: guard specs must fail safely (stub the heavy path to raise);
  the supervisor counts nesting depth in SABOTEUR_CHILD and refuses to fork
  past depth 4, a bound that does not depend on the guard.
- 2026-10-09 Dogfood CI job added (PRs, --since origin/<base>); action pins
  verified against GitHub tags.

- 2026-10-09 The restructure left dogfood's excludes pointing at moved files,
  so dogfood mutated the containment code; the watchdog tripped at 32
  processes / 3.1 GB and cleaned up. Fix: excludes updated, and a warning
  for any include/exclude pattern that matches no file.

- 2026-10-09 Process table read from the kernel (libproc on macOS via Fiddle,
  /proc on Linux, ps fallback): supervised child overhead 58.8 ms -> 7.9 ms.
  Pinned gems back to pre-containment speed; snapshots updated.

- 2026-10-09 Restructured into layers (see Architecture review). Not named
  `Saboteur::Coverage` on purpose: it would shadow Ruby's `Coverage` inside
  the namespace. `Saboteur::Rails` became `Frameworks::Rails` for the same
  reason.

- 2026-10-09 Tests per mutant are selected by line (innermost statement's
  first line through the edit's last line); unreached mutants are "no
  coverage", not survivors. Selected tests run prior killers first, then
  fastest first. (commits 9ce97fe, 7a08ca7; survey recs 1 and 2)
- 2026-10-09 Statement removal skips if/unless without else (same change as
  the condition mutants). (9ce97fe)
- 2026-10-09 Coverage recorder suspends Coverage while it processes deltas;
  fixture specs excluded from the suite. (bb5891a)
- 2026-10-09 Process containment: Supervisor tracks the whole descendant
  tree, stop-then-kill after every child, memory/process caps, RLIMIT_CPU
  backstop, parent-death check, INT/TERM cleanup, Linux subreaper;
  recursion guard via SABOTEUR_CHILD. Root cause and evidence in the commit
  message of 47b8bc8. Reviewed independently with Grok CLI, same root cause.
- 2026-10-09 macOS facts measured: RLIMIT_AS/DATA/RSS cannot be lowered
  below a Ruby process's reservation and are not enforced; RLIMIT_CPU is
  enforced (SIGXCPU); `ps -e` environment display is unreliable, so no
  environment-marker tracking.
- 2026-10-09 Statement removal only for sequences of 2+ statements; Stryker
  report lists tests once under testFiles; compact JSON. (1c85260)
- 2026-10-09 Pinned targets: dry-inflector b6a2819f, tty-color e2410967
  (MIT). rainbow rejected: its Gemfile pulls mutant-rspec (clean-room rule).
- 2026-10-09 Both re-evaluation strategies implemented; `class_eval` stays the
  default until question 1 is answered.
- 2026-10-09 Stryker JSON validated against the official
  mutation-testing-report-schema (json_schemer): all reports valid.

## Safety rules for heavy runs (learned the hard way)

- Never run saboteur on a project whose tests can start saboteur without the
  recursion guard; never disable it outside a bounded spec.
- One heavy job at a time; nothing alongside native gem compiles.
- Wrap dogfood / target / Rails runs in `script/watchdog` (process count,
  total RSS, wall time; kills the whole tree), e.g.
  `script/watchdog /tmp/x --procs 30 --rss-gb 6 --minutes 20 -- bundle exec exe/saboteur run`.
- Specs that fork or allocate must be self-bounding and clean up pids.

## Architecture review (principal-engineer pass, 2026-10-09)

Codebase: ~2.8k lines in lib/, flat `lib/saboteur/*.rb` plus four subdirs.

Findings:

1. `Engine` (346 lines) owns six jobs: boot lifecycle, subject selection,
   coverage cache/build, candidate generation and validation, per-subject
   scheduling (neutral check, coarse-first, test selection, prioritization),
   and result assembly. Phase 5 needs the scheduling unit on its own (it is
   what workers parallelize). Split into collaborators; Engine becomes a
   short pipeline.
2. Domain types live in the wrong files: `Edit`/`Mutation` are the public
   contract for external mutation sources but sit in
   `mutation_source/base.rb`; statuses live in `result.rb` while the
   resource-limit-as-timeout mapping lives in `runner.rb`.
3. The child protocol (JSON lines over a pipe) is implicit inside Runner.
   Phase 5 and any future worker model need it named and versioned.
4. Flat layout hides layers. Group by layer with matching namespaces
   (Ruby/Zeitwerk convention: directory == namespace):
   - `analysis/` Subject, SubjectFinder
   - `mutation/` Edit, Mutation; sources stay under the public
     `Saboteur::MutationSource` name (extension API, keep stable)
   - `execution/` Reevaluator, Runner, Supervisor, ProcessTree, Protocol
   - `selection/` CoverageMap, Recorder (own file), GitDiff
   - `reporting/` Result, Report, Diff, Terminal, Stryker
   - `integration/` RSpec (public adapter API, keep names)
   - `frameworks/rails.rb` (a profile, not a test adapter)
   - top level: Config, CLI, Hooks, IgnoreList, Engine
5. Public API surface is undeclared. Stable: `Saboteur::MutationSource::Base`
   + `Edit` + `Mutation`, `Saboteur::Integration::Base`, `Saboteur.hook`,
   config keys, CLI flags, report formats. Everything else `@api private`.
6. Config is an untyped hash; keys documented only in design.md. Move to a
   typed schema that also generates the config reference doc.

Plan (each step lands with the suite green):
- [x] A. Extract `Edit`/`Mutation` to their own files; `Recorder` to its own file
- [x] B. Split Engine: `Boot`, `SubjectSelection`, `CoverageStore`,
      `Candidates`, `Scheduler`, `Diagnostics` (lib/saboteur/engine/)
- [x] C. Layered namespaces: `Execution::` (Supervisor, ProcessTree, Runner,
      Reevaluator, Protocol), `Selection::` (CoverageMap, Recorder, GitDiff),
      `Frameworks::Rails`, `Reporter::Diff`. Public names unchanged:
      `MutationSource::*`, `Integration::*`, `Saboteur.hook`.
- [x] D. Name the child protocol (`Execution::Protocol`, versioned)
- [x] Naming pass: coverage_lines_for, live_members, stopped_by,
      leftover_pids, load_target, select, build_sources, inform,
      count_invalid_mutation
- [ ] E. Typed config schema + generated docs/config.md
- [ ] F. Mark `@api private` / public in YARD comments; document the public
      API in README
