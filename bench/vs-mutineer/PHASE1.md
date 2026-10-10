# saboteur vs mutineer: Phase 1 (setup and fairness)

Status: draft, waiting for review (STOP).
Date: 2026-10-10. Measured unless marked "estimate".

Targets (RSpec only, maintainer decision): addressable, hashie, lobsters,
human-essentials. Pins and green runs are in PHASE0.md.

Scope (maintainer decision, 2026-10-10): saboteur does not aim to support
Minitest. Minitest support is not scored as a mutineer win. The features
table lists it once, marked "out of scope by design".

## 1. How each tool is configured

Both tools get the same source files (configs/TARGET/sources.txt) and the
same spec files (configs/TARGET/tests.txt). `run_one` turns those lists into
each tool's own configuration, so neither tool can drift from the other.

| target | sources | spec files | notes |
|--------|---------|-----------|-------|
| addressable | 5 (lib, minus version.rb and the native IDNA backend) | 5 | IDNA_MODE=pure |
| hashie | 40 (lib, minus version.rb) | 34 (spec/integration excluded, as hashie's own .rspec does) | |
| lobsters | 48 (app/models, minus story_image.rb, which needs libvips) | 109 (all) | Ruby 4.0.0 |
| human-essentials | 136 (app/models, app/services) | 209 (system specs, the flaky file and 6 isolation-failing files excluded) | Postgres in Docker |

The flaky human-essentials example is excluded by leaving out its whole
file, because mutineer selects whole files and cannot drop one example.

Six more human-essentials spec files are excluded for both tools because
they fail when run on their own with plain RSpec (the suite is green only
as a whole; for example CustomDeviseMailer is defined only if an earlier
spec loaded it):

| file | alone |
|------|-------|
| spec/controllers/application_controller_spec.rb | 10 examples, 1 failure |
| spec/mailers/custom_devise_mailer_spec.rb | load error (NameError) |
| spec/pdfs/donation_pdf_spec.rb | 5 examples, 3 failures |
| spec/services/exports/export_report_csv_service_spec.rb | 5 examples, 4 failures |
| spec/services/sync_ndbn_members_spec.rb | 5 examples, 5 failures |
| spec/services/exports/export_adjustments_csv_service_spec.rb | 2 examples, 1 failure (3 of 3 runs) |

All 210 remaining files were then run one by one with plain RSpec
(raw/findings/human-essentials-isolation-check.txt); only the sixth file
failed. mutineer had reported these files a few at a time, across three
runs of about 13 minutes each.

mutineer checks each covering file on the unchanged code and refuses to
score when one fails ("the unmutated suite is not green"). That is a
reasonable safety check, but it means mutineer cannot run on a suite that
is green only as a whole. saboteur ran on the full set; its verdict check
turns kills by such tests into errors instead.

### What a user writes

| | saboteur | mutineer |
|---|---|---|
| Gem install | `gem "saboteur"` in the test group | `gem "mutineer", require: false` in the test group |
| Config file | `.saboteur.yml`: `include:` globs, `rspec_args:`, `rails: true` | `.mutineer.yml` optional; sources and `--test` files go on the command line |
| Lines of config, gems | 3 (`include:` plus one glob, plus an exclude line) | 0 (all on the command line) |
| Lines of config, Rails | 4 (`rails: true`, `include:`, two globs) | 0 (`--rails` flag) |
| Command, gem | `bundle exec saboteur run` | `bundle exec mutineer run lib/**/*.rb --test spec/a_spec.rb --test spec/b_spec.rb ...` (one `--test` per spec file) |
| Command, Rails | `bundle exec saboteur run` | `RAILS_ENV=test bundle exec mutineer run app/models/*.rb --test ... --rails` |
| Tests chosen by | the whole suite's per-example coverage | the `--test` files you list, narrowed by per-file coverage |
| Setup steps | 2 (gem, config file) | 1 (gem); the command line has to list every spec file |
| Setup time, this bench | about 5 min per target (estimate, by hand) | about 5 min per target (estimate, by hand) |
| Workarounds needed | lobsters: `gem "fiddle"` on Ruby 4.0 (saboteur bug 1) | human-essentials: `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` and `PGGSSENCMODE=disable`; without them coverage capture crashed 428 times (Objective-C fork-safety abort after boot, macOS) and the run stopped. Also needs the 6 isolation-failing spec files removed. |

For both tools the bench passes the identical lists; the rows above say
what a user would write by hand.

## 2. Operator modes

### (a) Defaults, as a user runs them

- saboteur: its one built-in set (it has no operator selection).
- mutineer: Tier 1, which is arithmetic, comparison, boolean_connector,
  boolean_literal and statement_removal.

### (b) Matched operators

saboteur 2b6ec02 cannot switch operators off, and the ref is frozen, so
saboteur runs its full set once. Mode (b) for saboteur is a filter applied
to that run's results. mutineer runs with `--operators` set to the closest
equivalents (matched-operators-mutineer.txt).

One caveat: saboteur's coarse-first rule skips a method's fine mutants
when a whole-method mutant (body_nil, body_true, body_false, body_raise)
survives. When those coarse operators are filtered out, the skipped fine
mutants stay missing. The report gives both counts.

| saboteur operator | what it does | mutineer equivalent | match |
|---|---|---|---|
| comparison | `<` to `<=`, `!=`, false; `<=` to `<`, `==`, true; `==` to false/true; `!=` to true/false (sufficient set) | comparison (`<`/`<=`, `>`/`>=`, `==`/`!=` swaps) | partial: same nodes, different replacements |
| arithmetic | `+`/`-`, `*`/`/` on non-literal operands | arithmetic (also `%` and `**` to `*`) | close |
| boolean_logic | `a && b` to `a`, to `b`, to false (`\|\|` to true) | operand_removal (`a && b` to `a`, `b`) | close; mutineer has no absorbing constant |
| condition_true / condition_false | if/unless/while/until predicate forced | condition_true / condition_false (also case-in guards) | match |
| negation_removal | `!x` to `x` | negation_removal (also `not x`) | match |
| safe_navigation | `&.` to `.` | safe_navigation | match |
| statement_removal | any statement (final included) in a sequence of 2 or more to nil, skipping logging and if-without-else | statement_removal (non-final statements to nil) | close; saboteur also removes the final statement |
| literal_number | integer/float to n+1, n-1, 0 | literal_mutation (integer to 0, 1, n+1; string to "") | partial |
| body_nil (coarse) | whole method body to nil | return_nil (each return value and the final expression to nil) | partial |
| body_false (coarse, predicates) | predicate body to false | return_nil (nil is falsy) | partial |
| body_true (coarse, predicates) | predicate body to true | none | no match |
| body_raise (coarse) | whole body to raise | none | no match |
| or_assign | `\|\|=` to `=` | none (operator_assignment skips `\|\|=`) | no match |

mutineer operators with no saboteur equivalent: boolean_connector (`&&` to
`\|\|`), boolean_literal, string_literal, regex, collection_method, range,
chain_link, array_literal, condition_negation, operator_assignment
(`+=` and similar).

Matched set, mutineer: arithmetic, comparison, operand_removal,
condition_true, condition_false, negation_removal, safe_navigation,
statement_removal, literal_mutation, return_nil.
Matched set, saboteur (filter): everything except body_true, body_raise and
or_assign.

### mutineer mutant counts (dry run, measured)

| target | defaults | matched |
|--------|----------|---------|
| addressable | 1,218 | 2,710 |
| hashie | 409 | 1,270 (1 invalid) |
| lobsters | 1,303 | 3,450 (8 invalid) |
| human-essentials | 1,237 | 3,789 (1 invalid) |

saboteur has no dry run, so its counts come from Phase 2's first run.
For reference, its earlier human-essentials run on the same scope made
4,080 mutants.

## 3. Same sources, same tests

Both tools read the same two lists. The bench also gives every run a cold
start: `run_one` deletes both tools' caches (.saboteur and
.mutineer-bench) first, unless BENCH_WARM=1.

## 4. Rails modes

| app | saboteur | mutineer | why |
|-----|----------|----------|-----|
| lobsters (SQLite) | jobs 6 and jobs 1 | jobs 1 only | mutineer 1.6.0's `--daemon`, its only parallel Rails mode, rejects RSpec: "--daemon supports only --framework minitest (rspec is not implemented on the daemon path yet)" (raw/findings/mutineer-daemon-rspec.txt). `--rails` without `--daemon` forces one worker. |
| human-essentials (Postgres) | jobs 6 and jobs 1 | jobs 1 only | as above; also, per its README, `--daemon` on Postgres scores every mutant as error |

mutineer strategies: `--rails` defaults to `redefine`. Both `redefine` and
`reload` run on both apps. On the gems the default is `reload`; both run
there too.

Planned worker count for parallel runs: 6, the same for both tools where a
tool can run in parallel. The gems run both tools at jobs 6 and at jobs 1.

## 5. Status mapping

| bench status | saboteur (Stryker JSON) | mutineer (JSON) | in score? |
|---|---|---|---|
| killed | Killed | killed (counted in summary; listed per mutant only with `--matrix`) | yes |
| survived | Survived | survived (`survivors` list) | yes |
| timeout | Timeout | timeout | no (both tools leave it out) |
| error | RuntimeError (also kills that the verdict check overturned) | errored (`no_verdict` list) | no |
| resource_limit | RuntimeError, reason starts "resource limit:" | none (no memory or process caps) | no |
| no_coverage | NoCoverage | no_coverage | no |
| subsumed | Ignored, reason "coarse mutant survived" | none | no |
| ignored | Ignored, ignore-list reason | ignored | no |
| ran_at_load | none | ran_at_load (a survivor on a line that ran at boot) | no |
| no_verdict, other | Ignored, other skip reasons (not loaded, refinements) | uncapturable, unplaceable | no |
| invalid | counted in the run summary only | skipped_invalid | no |

## 6. Gaps that shape Phase 2

1. mutineer's normal JSON report does not list killed mutants or the killing
   test, and neither tool's JSON gives a failure message for a kill.
   The false-kill audit therefore uses one neutral harness for both tools.
   For each sampled kill it applies the mutant as a byte edit, runs the
   killing test in a fresh process on the unchanged code and on the mutated
   code, and records the failure class and message. For mutineer, the
   killing tests come from a `--matrix` run (verdicts are the same as a
   normal run, per its README); speed numbers come from normal runs only.
2. Early smoke result, not yet a measurement: on lobsters tag.rb, saboteur
   turned one kill into an error. Its killing test,
   spec/features/submit_story_spec.rb[1:10], also fails on the unchanged
   code when it runs after the tests before it ("Domain has already been
   taken"). Phase 2 measures how often each tool counts such kills.
3. Estimated runtime is large. On human-essentials, mutineer is serial and
   runs whole spec files per mutant. Section 7 gives the measured per-mutant
   cost and a proposed scope.

## 7. Smoke runs (one file each, measured)

| target / file | tool | jobs | mutants | killed | survived | no cov | other | wall |
|---|---|---|---|---|---|---|---|---|
| hashie clash.rb | mutineer | 6 | 10 | 7 | 0 | 3 | 0 | 12.2 s |
| hashie clash.rb | saboteur | 6 | 47 | 30 | 2 | 15 | 0 | 2.6 s |
| lobsters tag.rb | mutineer | 1 | 11 | 9 | 0 | 2 | 0 | 192.0 s |
| lobsters tag.rb | saboteur | 1 | 51 | 30 | 9 | 9 | 2 ignored, 1 error | 108.9 s (coverage map was warm) |

saboteur also ran on Ruby 4.0.0 (lobsters) once fiddle was in the bundle.
