# Phase 4: a Rails app (rubyforgood/human-essentials)

> Measured before the coarse-survivor gate was removed and before the
> rebaseline. Mutant counts, skips and times here are historical; a rerun is pending.

Target: rubyforgood/human-essentials at d6f829046ee9696499f6781fc8f9e434d270a2be
(MIT licence), Rails 8.1, Postgres 16 in Docker, Ruby 3.4.3. Test env only,
no network from tests. Config: integration/configs/human_essentials.rb
(app/models and app/services; system specs excluded).

Scope: 136 files, 664 subjects, 4,202 candidate mutations.

## Baseline suite (system specs excluded), under script/watchdog

| run | examples | failed | pending | wall | peak RSS | leftovers |
|-----|----------|--------|---------|------|----------|-----------|
| 1   | 2,415    | 0      | 1       | 155.5 s | 816 MB | 0 |
| 2   | 2,415    | 0      | 1       | 153.4 s | 742 MB | 0 |
| 3   | 2,415    | 0      | 1       | 153.5 s | 730 MB | 0 |

No example changed status across the three runs. Three runs cannot rule out
flaky tests.

The app starts SimpleCov from its test environment. Saboteur now turns
SimpleCov.start into a no-op for the run (Boot.silence_simplecov), because it
needs Ruby's Coverage itself.

## First scoped run: --subject Item (19 subjects, 98 mutants), jobs 1

| design | wall | map build | mutants+checks | killed | survived | error | skipped |
|--------|------|-----------|----------------|--------|----------|-------|---------|
| neutral check before mutants | 754 s | 260 s | ~494 s | 85 | 11 | 0 | 2 |
| verdict check, no calibration | 251 s | cached | 251 s | 84 | 11 | 1 | 2 |
| verdict check + timeout calibration | 263 s | cached | 263 s | 85 | 11 | 0 | 2 |

Verdicts of the last row equal the first, mutant by mutant. Peak RSS 1.2-1.4
GB, at most 4 processes, no leftovers. The map build (260 s) is 1.7x the
plain suite (155 s), paid once per cache key.

Why the neutral check went: Item#set_default_distribution_quantity and
Item#default_distribution_quantity are callbacks every Item factory runs;
each has ~850 covering tests (121 s). Their neutral checks alone cost more
than all of Item's mutants. The error in the middle row was a false timeout
(the recorded durations were too tight for a fresh child); the check caught
it, and calibration (a real unchanged run on a timeout) now sets it right.

Kills: 68 by a failed assertion, 17 by a crash (RuntimeError 12 from
body_raise, NoMethodError 3, CSV::MalformedCSVError 1,
ActiveRecord::RecordNotDestroyed 1).

Survivors (11), first read (to be classified with the full run):
- Item#default_quantity: `distribution_quantity || 50` -> `|| 51`, `|| 49`,
  `|| 0`, and dropping `|| 50`: no test pins the default of 50.
- Item#has_inventory?: both `&.` -> `.` mutants survive: no test calls it
  with no inventory, or with an item missing from the inventory.
- Item#is_in_kit?: `if kits` -> `if false` survives: the kits argument path
  gives the same answer as the query path in every test.
- Item.reactivate: dropping `Array.wrap(item_ids)` survives (likely
  equivalent: `where(id:)` accepts a scalar or an array).
- Item#can_deactivate_or_delete? and #set_default_distribution_quantity:
  `||=` -> `=` survives (M3 keeps these; the first looks equivalent when
  callers never pass an inventory in tests).
- Item#sync_request_units!: `if limit.present?` -> `if true` survives: no
  test passes a blank limit.

## Parallel workers: --subject Item, --jobs 3

| run | wall | killed | survived | error | note |
|-----|------|--------|----------|-------|------|
| first try | 6.7 s | 0 | 0 | 96 | workers died silently; then: no PoolConfig#connection_class (Rails 8) |
| + owner_of | 7.7 s | 0 | 0 | 96 | children SIGSEGV: libpq GSSAPI probe after fork (macOS) |
| + PGGSSENCMODE=disable | 105 s | 20 | 1 | 75 | PG::UndefinedTable: workers on the maintenance DB |
| + MaintenanceRecord, all roles | 142 s | 85 | 7 | 4 | SIGXCPU at ~4-5 s CPU of a 17-25 s limit |
| + checked SIGXCPU | 142 s | 85 | 11 | 0 | identical to --jobs 1, mutant by mutant |

Peak RSS 3.3 GB (watchdog sum over the tree), at most 11 processes, no
leftovers. Speed-up 1.85x on 3 jobs: one subject (the ~850-test callback,
whose `||=` survivor runs every test, ~121 s) bounds the wall time.

## Full scope: app/models + app/services, --jobs 6 (2026-10-10)

664 subjects, 4,080 mutants (after dropping duplicates and edits that do not
parse), wall 3,602 s, peak 20 processes, peak RSS 6.7 GB (watchdog sum over
the tree), no leftovers.

| killed | survived | timeout | resource limit | error | skipped |
|--------|----------|---------|----------------|-------|---------|
| 3,510  | 452      | 1       | 0              | 0     | 117 (67 no coverage, 50 coarse mutant survived) |

Score 88.6 %. Mean 3.3 s per executed mutant. Kills: 2,388 by a failed
assertion, 1,122 by a crash (RuntimeError 467, mostly body_raise; NoMethodError
358; NameError 167; ActiveRecord::RecordInvalid 41; ...).

Zero errors over 4,080 mutants on a real Rails app is the main result: every
kill and timeout was re-checked against the unchanged method and held. The
verdict check does not re-run survivors. Survivor classification (30+) is next.
