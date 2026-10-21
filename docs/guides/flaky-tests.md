# Saboteur vs flaky tests

Mutation testing asks one question thousands of times: *does the suite fail
when the code changes?* A flaky test makes every answer untrustworthy, so
saboteur treats suite instability as a stop condition, not a warning. This
page shows what that looks like on a real suite and what to do about it.
The examples come from a 0.7.0 run on [publify](https://github.com/publify/publify)
with a deliberately flaky spec added.

## What saboteur already does

- **Two baseline passes before any mutant runs.** The unchanged suite runs
  twice (config `c.baseline_passes`, preset-dependent). A suite that cannot
  pass twice in a row stops the run at exit 5, before a single mutant is
  attributed to it.
- **An unchanged-method check per kill.** A mutant whose killing test also
  fails against the *unchanged* method is rejected - the kill was the
  suite's mood, not the mutant.
- **Order and process hygiene.** Leftover child processes after the suite
  fail the run (with a known false-positive class, see below).

## What a flake looks like

A spec that passes on odd invocations and fails on even ones, added to an
otherwise green suite:

```
saboteur: checking the unchanged suite twice (seed 1)
saboteur: baseline check 1 took 1 s; about 2 s left for the remaining 2 full passes at that rate
saboteur: baseline check 2 failed at seed 1: the suite failed: ./spec/models/flaky_demo_spec.rb[1:1]. The log says:
  Failures:
    1) Flaky demo fails every second run
       Failure/Error: expect(count.even?).to be(true), "flaked on run #{count}"
         flaked on run 1
See the full log at .../.saboteur/baseline-2.log. Fix the suite or its setup, then run saboteur again with the same seed. No mutants were started.
```

Read the shape, not the wording: the refusal names the spec file and
example id, quotes the failure, and points at the full baseline log.
**No mutants were started** - a red baseline never produces a score you
have to second-guess. With the `pr` preset (`--baseline-passes 1`) the same
flake surfaces one phase later, as `coverage map build failed: the
unchanged suite failed while building coverage` - one baseline pass cannot
catch an every-second-run flake before the map build runs the suite again.

After deleting the flake, the same command with the same seed goes back to
green (`killed 18  survived 0 ... score 100.0 %`, exit 0). Rerunning with
the printed seed reproduces the run exactly; it does not freeze the flake.

## Fixing the suite, in the order that works

1. **Find the order or state dependency.** Most Ruby flakes are leaked
   state: records without transactional cleanup, class variables, globals,
   files in a shared tmpdir, `Time.now`/`rand` without a seed, or order
   coupling only visible under `--seed` randomization. The baseline log
   and the named example id are the starting point.
2. **Check the boundary resources.** Database connections inherited across
   forks, background threads (the AR pool reaper is known-harmless and
   reported as such), and clocks all flake differently under saboteur's
   forking runner than under plain `rspec`. `saboteur doctor` checks the
   known environment problems first.
3. **Quarantine, don't ignore.** A flaky test excluded via RSpec tags
   keeps the run honest; deleting its coverage from the run hides real
   signal. Fix or quarantine - do not add flaky survivors to the ignore
   file, which answers a different question.
4. **Rerun with the printed seed** to confirm the fix before resuming
   normal runs.

## Known edge: a green suite can still be refused

A baseline can fail on a *passing* suite: the process-hygiene check reports
"the suite left child processes behind" and the quoted log shows
`0 failures`. That is the refusal working as designed (mutant runs must be
able to kill their children) - but one shape of it is a false positive
under investigation (#486: a green webmock suite refused with an empty
Failures section and no leftover processes visible). If you hit it, the
baseline log (`.../.saboteur/baseline-N.log`) and `ps` output from the
same moment decide which side you are on; report the pair on the issue.

## The bounded recheck: --flaky-check

Since 0.8.0, `--flaky-check survivors` gives each new survivor one
reordered confirmation rerun, and `--flaky-check decisive` does the same
for every fresh kill as well. A verdict the confirmation disagrees with
becomes `unverified` - named with its decisive tests, outside the score,
never retried until it passes. The check is opt-in and bounded to one
rerun per verdict, so a test that flakes in lockstep with the mutant can
still slip through: the double baseline, the unchanged-method check, and
suite hygiene above stay the base defenses.

Related: [Check a project before mutation testing](doctor.md),
[How to read survivors](reading-survivors.md).
