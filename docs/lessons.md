# Lessons

One entry per failure that reached the maintainer or an external reviewer.
Format: what happened, root cause (code / test / claim / plan), and the rule
or check that now prevents the whole class. New lessons are appended by the
review-to-checks loop in [agents/review-to-checks.md](agents/review-to-checks.md).

## 1. Confirmation pass crashed with exit 70

- What happened: `Engine` called the private `Scheduler#map`. The unit spec
  used `double("scheduler")`, so the real wiring never ran and the crash
  shipped.
- Root cause: test. Wiring between two real objects was verified with a
  double, not through the real CLI.
- Prevented by: the Wiring evidence rule in AGENTS.md (wiring changes need
  an e2e spec through the real CLI; unit specs with doubles are not
  evidence for wiring).

## 2. CHANGELOG 0.11.2 claimed "ending false survivors"

- What happened: the change was presentation-only by design, but the
  CHANGELOG entry claimed false survivors were ended.
- Root cause: claim. The entry described hoped-for behavior, not measured
  behavior.
- Prevented by: the Claims evidence rules (claims describe measured
  behavior; "presentation only" when true; overstatements get a
  "Corrected" entry) and `rake claims:check` (no `(e2e: ...)` reference,
  no claim). The 0.12.2 "Corrected" section records the fix.

## 3. The first e2e for that fix passed by construction

- What happened: the fixture added `lib/flow.rb`, so `flow_spec.rb` was
  inferred by name; the e2e passed because of the fixture shape, not the
  fix.
- Root cause: test. The fixture was the easiest passing one, not the
  user's situation.
- Prevented by: the Fixtures evidence rule (test-selection fixtures include
  a spec with NO same-named source file; every e2e spec comments the
  real-world case it models) and the `router_pr` acceptance scenario.

## 4. An inferred-spec map was recorded as "whole-suite"

- What happened: a default full run recorded an inferred-spec map as
  whole-suite, producing a false "covered by X - ran, still passed" claim.
- Root cause: code and claim. Provenance of the map was not distinguished,
  and the report text overstated what the covering list meant.
- Prevented by: the Claims evidence rules and the `router_pr` acceptance
  scenario (no map: "survivors unconfirmed", no block contains "ran, still
  passed").

## 5. CHANGELOG 0.12.0 claimed input_gap was "separate from assertion gaps"

- What happened: the claim was written before `assertion_gap` existed. It
  described behavior the code did not have.
- Root cause: claim.
- Prevented by: the Claims evidence rules (`rake claims:check`; the 0.12.2
  "Corrected" section records the fix).

## 6. Gap labels were computed from the initial run only

- What happened: once confirmation ran other specs, the label computed from
  the initial run was wrong.
- Root cause: code. The label did not account for all surviving mutants of
  the statement.
- Prevented by: the Wiring and Negative-check evidence rules and the
  `fx_gap` acceptance scenario (`gapKind`, `valueDiffered` checked on the
  real CLI).

## 7. A feature plan proposed what already existed

- What happened: a plan proposed per-mutant timeouts, PR review comments
  and incremental stats, all of which already existed.
- Root cause: plan. The plan was written without searching the code, docs,
  `--help` output or CHANGELOG.
- Prevented by: the Plans evidence rule (quote what exists; a plan item may
  not describe existing behavior as missing).

## 8. A `--no-color` bug was fixed in one subcommand only

- What happened: the same bug stayed in the sibling subcommands.
- Root cause: code. The fix was not swept across siblings.
- Prevented by: the Sibling-sweep evidence rule (search all siblings; fix
  or list them in the pull request).

## 9. A suite with failures was reported as "green"

- Class: validation overstatement.
- What happened: during the #1312 validation (Oct 23), a full-suite run
  finished with `EXIT=1`, 7947 examples and 4 failures. The first report
  called it "FULL VALIDATION COMPLETE - green". A follow-up one minute later
  corrected it to "7943/7947 pass with 4 failures, NOT green".
- Root cause: claim. The verdict word was written before it was reconciled
  with the exit code in the same message.
- Prevented by: the mechanical-evidence rule (no "green"/"passing"/
  "validated" without the command and its output in the same message; if it
  was not run, say "not run"). The exit code is part of the pasted output,
  so the word and the number cannot drift apart.

## 10. A dogfood run with a `--test` override was reported as the CI mirror

- Class: validation overstatement and wasted run.
- What happened: the first #1316 dogfood gate was run with explicit `--test`
  flags from a `/tmp` clone, bypassing spec inference, so it did not count
  as the CI-mirror gate. It was re-done as the true CI mirror (default
  inference, HOME-placed worktree) before the gate was accepted.
- Root cause: claim. The evidence came from a different invocation than the
  one the gate exists to mirror, and the report did not flag the difference.
- Prevented by: gate reports carry the full command line and working
  directory. A dogfood run only counts as the CI mirror with default spec
  inference and no `--test` flags; any deviation is named in the report.

## 11. A suite was claimed to run in HOME while it ran in /tmp

- Class: validation overstatement; the same placement mistake also wasted
  diagnosis effort.
- What happened: the #1315 combined validation was reported with "HOME
  placement" while the suite's working directory was `/tmp/p4comb`. The
  placement mattered: earlier the same day, `/tmp` placement caused four
  sandbox-grant spec failures in the #1312 full suite that then needed
  causal isolation. The claim was corrected after the running process's
  real cwd was inspected.
- Root cause: claim. Placement was asserted from intention, not verified
  from the running process.
- Prevented by: placement claims are verified against the live process
  (`/proc/<pid>/cwd`) and quoted with the command's output. Suites run from
  a HOME-placed worktree so sandbox-grant specs see the same shape as CI.

## 12. A "measured floor" mixed a complete and an incomplete CI run

- Class: measurement overstatement.
- What happened: a "13-15 minute measured floor" for CI was derived partly
  from a run whose platform coverage was incomplete (the macOS legs never
  ran). The complete run measured 5m37s; the floor was retracted.
- Root cause: claim. A number was presented as measured without naming the
  runs it came from, so an incomplete run was averaged in.
- Prevented by: every timing claim names the exact run IDs it is derived
  from, with each run's completion status. Incomplete runs are excluded and
  said to be excluded.

## 13. A commit timestamp was reported as the push time

- Class: reporting error.
- What happened: during #1318 recovery, a commit's author timestamp was
  reported as the time the commit was pushed ("pushed at 09:05:50",
  "execution unblocked"). The push had in fact happened later, and the
  claim was corrected.
- Root cause: claim. An event on the remote was inferred from local
  metadata instead of being checked against the remote.
- Prevented by: claims about remote state (pushes, run status, coverage)
  are verified against the remote (`git ls-remote`, `gh api`) at report
  time; local timestamps are not evidence for remote events.

## 14. Two CI runs were wasted on dispatch mechanics

- Class: wasted runs.
- What happened: for #1318, one `workflow_dispatch` ran at `ref=main` and
  tested the wrong code (cancelled), and the next ran without the head
  repository input, so the macOS legs never ran and platform coverage was
  incomplete. A third dispatch with all inputs produced the usable green.
- Root cause: process. Dispatch inputs were not verified before triggering,
  and the run's head SHA and job list were not inspected before treating it
  as coverage.
- Prevented by: CI confirms, never discovers. Before dispatch, verify ref,
  head repository and PR number; after dispatch, inspect the run's head SHA
  and job list before citing it as evidence. One dispatch with all inputs,
  not a retry chain.

## 15. An "exact tree" claim held while the worktree had uncommitted changes

- Class: validation overstatement.
- What happened: a #1314 validation suite was relaunched as an "exact-tree"
  run while unrelated uncommitted README content sat in the validation
  worktree. The content was stashed and the run restarted after the
  mismatch was caught.
- Root cause: claim. Tree-exactness was asserted without checking the
  worktree against the commit.
- Prevented by: a tree-exact claim requires `git status` clean and
  `git diff --quiet HEAD` on the validation worktree, quoted in the same
  report. `git write-tree` on the actual worktree must equal the stated
  tree hash.

## 16. Three overlapping suite runs produced one unusable log

- Class: wasted runs.
- What happened: during #1314 diagnostics, retry launches left three rspec
  processes writing interleaved to one log. The kill pattern
  (`pkill -f "bundle exec rspec"`) never matched the real process name, so
  nothing was killed. The log was discarded as evidence and the affected
  old-base diagnostic full runs were declared dead; the prospective
  combined tree made them unnecessary anyway.
- Recurrence, same day: during the final full-gate launch, a first
  mis-configured attempt (a CLI `--exclude-pattern` overrode the `.rspec`
  fixtures exclusion, so a fixture spec failed to load: exit 1 in about a
  second, zero examples run) was stopped with a broad pattern
  (`pkill -f "rspec spec/e2e"`) that also matched and killed the older
  diagnostic e2e run about 78 minutes in, against an explicit
  no-interrupt instruction. That run's evidence ends discarded (about 280
  example dots, no failure lines, no final summary or exit) and it was
  not rerun. The mis-launch was never treated as evidence: the corrected
  launch targets the unit directories explicitly and was verified by a
  dry-run example count (7593 examples) before starting.
- Root cause: process. The kill was attempted with an assumed pattern
  instead of the observed process name, and duplicate long runs were
  started before the previous one's state was known. The recurrence is
  the same class with the opposite match failure: selection by
  command-line substring matched more than the target, so a protected
  run died with it.
- Prevented by: one long run per lane at a time; before relaunching, list
  matching processes (`pgrep -af`) and kill by verified pid/pgid. Signal
  only the captured identity: the pid or process-group id recorded at
  launch, re-verified by command line and ancestry immediately before
  signaling; never a broad pattern while any other run is alive. Before
  any long run, state the expected result and the decision it drives; a
  run whose evidence is discarded is reported as discarded, not silently
  replaced; an interrupted run is not counted as completed and is not
  rerun without authorization. Verify a launch's test selection with a
  dry-run example count before the real run starts.

## 17. A conflicted `git am` silently committed only the resolved file

- Class: near-miss (not an overstatement; the check caught it).
- What happened: during the #1313 restack, a conflicted `git am` was
  resolved by hand and committed only the manually resolved e2e file,
  silently dropping the rest of the patch. The write-tree comparison caught
  it mid-restack, before any PR, at the cost of redoing the staging.
- Root cause: process. Conflict resolution bypassed the tree check that
  clean applies get.
- Prevented by: the write-tree check runs after every `git am` or rebase,
  including conflicted ones: `git write-tree` must equal the stated target
  tree before the result is reported, and the report quotes the command and
  output. This entry stands as evidence the check is worth its cost.

## 18. An overlap claim was drafted from a truncated diff

- Class: near-miss (caught internally before it drove an action).
- What happened: a file-overlap claim between two staged patches was
  derived from a diff stat read through `tail`, which had cut off part of
  the file list. The claim ("does not touch diagnostics.rb") was wrong and
  was reversed after the full stat was read.
- Root cause: claim. A file list was derived from truncated output.
- Prevented by: file lists come from full `git diff --numstat` or
  `--name-only` output. Never derive scope from a `tail` of a stat.

## 19. A direct push put a lint-red script on main

- Class: process gap (check missing on a review-waived route).
- What happened: a harness slice pushed straight to main added
  `script/claims-check` with 9 rubocop offenses (782 files checked). Main
  was lint-red and every product PR's preflight blocked until a corrective
  slice landed.
- Root cause: process. The direct-to-main route had no local lint gate; a
  maintainer waiver of PR review was treated as covering correctness too.
- Recurrence, same day: a later direct slice landed five new e2e specs
  after linting only three of the changed files; an independent whole-head
  run (787 files) caught a `Style/StringConcatenation` offense in the
  unlinted fourth file. Partial file-list lint is not the gate.
- Root cause: process. The direct-to-main route had no local lint gate; a
  maintainer waiver of PR review was treated as covering correctness too.
- Prevented by: a direct push that adds or changes any Ruby file, script,
  spec or workflow requires the fast preflight
  (`ruby script/preflight --base <main sha> --head <head sha> --base-ref
  main --mode fast`, about 45 seconds) green on the exact post-apply head,
  which includes whole-repo rubocop with no file subsetting, pasted as raw
  output in the push report and re-executed independently where a
  toolchain is available. The review waiver never waives checks. A fast
  preflight is partial: never report it as the full suite.

## 20. A capacity root cause was claimed, then withdrawn as unproven

- Class: causal overstatement.
- What happened: agent failures during #1318 recovery were attributed to
  retry contention. The claim was later withdrawn: it was correlation, and
  evidence from the same window argued against it.
- Root cause: claim. A causal story was asserted from correlation.
- Prevented by: causal claims about the environment are labeled as
  hypotheses until reproduced, and the report names the observation and the
  test that would confirm or refute it.

## 21. Expected results were nearly reinterpreted to match the code

- Class: near-miss (proposal overruled before it took effect).
- What happened: when the acceptance prototype found the fx_gap expectation
  (`gapKind: assertion_gap`) disagreed with the JSON the code emits, a
  reinterpretation of the expected field was proposed. It was overruled:
  expected results are the maintainer's, transcribed exactly; the mismatch
  is reported as a discrepancy, not edited away.
- Root cause: plan. The fixture was being adjusted to the code instead of
  the code being measured against the maintainer's expectation.
- Prevented by: the acceptance immutability rule in AGENTS.md (never edit
  files under `acceptance/` or the expected results in them) and the
  CI guard that fails any agent PR touching `acceptance/expected.yml`.

## 22. Round over round, half-done fixes were accepted as done

- Class: validation overstatement (systemic).
- What happened: across the external review rounds, fixes were accepted
  that were presentation-only or half the requested behavior (review #3's
  C1 and D6; round-4 items P0, P1, P5 and P7 all traced to incomplete
  earlier fixes, per the Oct 22 recap). The reviewer found them again the
  next round.
- Root cause: claim and acceptance. "Fixed" was accepted without an e2e
  that demonstrates the claimed behavior.
- Prevented by: the harness as a whole: `rake claims:check` (no claim
  without an e2e reference), the acceptance suite, the negative-check rule
  (a bug-fix e2e must fail on the parent commit), and the independent
  reviewer whose report must show no open blocker before release.

## 23. Mid-review environment losses forced repeated re-runs

- Class: wasted work.
- What happened: twice during the batch, a review sandbox was rebuilt
  mid-work (worktrees, logs and in-flight runs lost). Completed checks had
  to be re-derived and in-flight ones restarted.
- Root cause: process. Work in progress lived only in scratch storage.
- Prevented by: durable checkpoints before any long validation: every patch
  is sent as an attachment, and gate state is reported with the exact
  head/tree it covers, so a rebuilt environment resumes from the last
  checkpoint instead of repeating the work.

## 24. Reports carried placeholder or mistyped SHAs

- Class: reporting integrity (recurring).
- What happened: across Oct 19-23, at least seven reports had to be
  re-issued because a SHA, tree hash or count was a literal shell
  placeholder, a tree hash typed as a head, or a mis-added number (examples
  on Oct 19 alone: a wrong v3 head, a placeholder rebase head, a tree sent
  as a head; on Oct 23 a verdict carried a mistyped tree-hash prefix and a
  shell placeholder). Each needed a correction message before the value
  could be used.
- Root cause: claim. Values were typed from memory or left as unexpanded
  shell substitutions instead of being pasted from command output.
- Prevented by: paste hashes and counts from the command output that
  produced them; a report containing a placeholder is re-issued before
  anyone acts on it. The mechanical-evidence rule covers the general case.

## 25. A full suite ran against the wrong loaded JSON gem

- Class: wasted run (preventable preflight miss).
- What happened: a full unit suite (7584 examples, about 16 minutes) for
  the #1316 validation failed exactly one example: an agent-report pin
  expected `"warnings": []` and got the pretty-printed `[\n\n]` form. The
  sandbox toolchain loaded the default gem json 2.7.1 while
  `Gem.loaded_specs` reported the lockfile pin 3.1.0. A probe of the
  actually loaded library (`require "json"; puts JSON::VERSION` plus
  `$LOADED_FEATURES` paths) showed 2.7.1 loading from the default-gem
  directory; after the toolchain fix it showed 3.1.0 from the pinned path.
  On the same head, re-introducing the shadow reproduced the identical
  one-example failure (7 examples, 1 failure, same diff) and the corrected
  toolchain passed (7 examples, 0 failures). Standing guidance had already
  warned about this exact default-gem shadow class after an earlier prism
  conflict; only `Gem.loaded_specs` was checked before the long run, so the
  failure cost the full run. A second long run launched before the fix also
  carried the wrong version.
- Root cause: process. The preflight verified the lockfile spec, not the
  actually loaded library.
- Prevented by: before any long run, the toolchain preflight asserts the
  loaded version of pinned native/default gems (`require` then the runtime
  VERSION constant equals the lockfile pin) and records the
  `$LOADED_FEATURES` paths. `Gem.loaded_specs` output is not proof of what
  is loaded. A wrong-toolchain run is closed only for the failure that was
  causally reproduced wrong-vs-right on the same head; its other results
  are not automatically carried as final gate evidence.

## 26. A sorted tail was read as the whole tag list

- Class: validation overstatement.
- What happened: while fixing the claims checker, the tag list was read
  through `git tag --list 'v*' | tail -3`. Lexical ordering ends with
  v0.8.0, v0.8.1, v0.9.0 ("0.10" sorts before "0.8"), so the sample looked
  like the whole set and became the claim that released versions past
  v0.9.0 were untagged upstream, with a tag backfill proposed. A live
  `git ls-remote --tags` showed all 18 release tags (v0.1.0 through
  v0.12.3) present, each an ancestor of main and matching a GitHub
  release; the author retracted (`sort -V | tail -4` shows v0.12.0 through
  v0.12.3). A related number, "344 checker failures", came from a stale
  local tree (a pre-0.12.3-release CHANGELOG) with no tags fetched; on
  current main the fixed checker reports 15 failures (14 README bullets
  plus the historical 0.0.1 skeleton bullet). No tag was written.
- Recurrence, same day: a "main lineage replaced" loss alarm was raised
  from a clone whose `origin` was a local mirror directory, not GitHub.
  The mirror's stale state (a forced-update fetch line and a four-commit
  history) was reported as the live main. It was retracted within
  minutes, with no writes made: `git ls-remote` of the canonical GitHub
  URL and the GitHub branch API agreed on the actual head, and the real
  lineage was intact. The alarm came from a tracking ref whose remote's
  identity was never checked.
- Root cause: claim. The extent of a versioned set was derived from the
  tail of a lexically sorted list, and a stale working tree was treated as
  current main. The recurrence adds a third form: a remote-tracking ref
  was read as the remote itself.
- Prevented by: never read a sorted tail as the extent of a versioned set;
  use `sort -V` and count the full list. Claims about remote state need a
  live `git ls-remote` (or API) quoted in the same report. Before any
  claim or alarm about the remote's state, verify the remote's identity
  first: `git remote -v` checked against the canonical URL, because a
  local mirror or a stale tracking ref is not the remote; then read the
  canonical URL itself with `git ls-remote <url>` or the API. Diagnostic
  runs state the exact tree they ran on: "current main" means a fresh
  fetch and a quoted `git rev-parse`.

## 27. A shipped checker's second input path was dead code

- Class: validation overstatement.
- What happened: the claims checker shipped in the first harness slice
  called `.each_line` on the CHANGELOG's path string instead of reading
  the file, so the CHANGELOG half of the check always returned no sections
  and never ran. The slice's verification ("passes on a clean tree, fails
  on the current README") exercised the README path only, so the dead path
  shipped. It was found when a spec for the CHANGELOG path failed for the
  wrong reason (expected one checker failure, got zero).
- Root cause: test. The checker landed without a failing-then-passing
  spec for each of its input paths, and the verification claim did not
  name which inputs were exercised.
- Prevented by: every check lands with a spec per input path that fails
  when the check is disabled and passes when it runs (a negative check for
  the checker itself). Verification claims name each input exercised.
## 28. The acceptance runner's RUBYLIB shadowed the gate's prism

- Class: environment parity (local baseline did not transfer to the gate).
- What happened: the acceptance runner unconditionally put the running
  Ruby's stdlib dirs on the child's RUBYLIB, a workaround one Ruby build
  needs to resolve its own stdlib. RUBYLIB entries shadow gem activation,
  and a stock Ruby 3.3 ships prism 0.19 in rubylibdir, so on CI the
  bundled 0.19 overrode the gemspec's prism 1.x. The first live
  acceptance run (39928487173) died in all 8 cases with a
  Prism::ParseResult superclass mismatch (exit 70); the crash masked
  every assertion, so the run said nothing about the product. The
  controlled product-break proof on that baseline hit the same crash,
  was recorded inconclusive, and closed unmerged. Local runs reached the
  assertions with only the two frozen expectation failures; the local
  Ruby lacked bundled Prism in rubylibdir: the shadow never fired
  there.
- Root cause: process. A workaround for one Ruby build's stdlib layout
  was applied unconditionally, and the gate environment's different
  layout was never probed. The local baseline was environment-narrow.
- Prevented by: the runner keeps the child's RUBYLIB to the project lib
  and appends stdlib dirs only for builds that fail a once-per-runner
  probe (`require "rubygems"` with RUBYLIB/RUBYOPT cleared). An
  acceptance run whose cases all die with the same internal error is an
  infrastructure failure, not a product result: stop, diagnose the
  runner, and re-run before drawing any product conclusion from it. A
  mechanism is claimed only after a same-head wrong-vs-right
  reproduction plus a gate run on the fix (run 39930740816: 8 cases, 6
  pass, exactly the two frozen expectation reds; the repeated controlled
  break then added exactly the predicted third red).

## 21. A field-run window went to preparation for a release that did not exist

- Class: process gap (a missing required input treated as a wait, not a
  stop).
- What happened: a field-evidence task pinned saboteur to the upcoming
  0.13.0 release and spent its window preparing app environments while
  the release was still in progress. The window closed with saboteur
  never run against any app; the report that reached the maintainer was
  honest about it, but the goal - measured runs - was never reachable
  within the window.
- Root cause: plan. A required input (the release) was missing from the
  start, and the task consumed its timebox on preparation instead of
  stopping to ask for the input or a re-scope.
- Prevented by: the missing-input rule in AGENTS.md ("Run discipline"):
  if a required input is missing - a release, a SHA, credentials, a
  decision - stop within 15 minutes and ask; do not spend a timebox on
  work that cannot reach the goal. The re-scope the task needed (pin
  current main, record the SHA, build the gem from it) is what the
  15-minute ask would have produced.
