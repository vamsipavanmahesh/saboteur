# Independent verification packet 1 (2026-10-24, verifier box)

Fresh independent verification from the triage agent's own box
(Ubuntu 22.04, 2 CPU / 1.9GB; deviations in out/DEVIATIONS.md).
saboteur 0.12.3 built from pinned source
6f87ccc98377bf0c23f3cf409006f0464c2aa67c (verifier gem sha256
16ef8af613ad2d1e010e08c585586807aaa2a33ac0f604d5828236981b63c9a1;
same commit, not byte-reproducible vs producer's 7f5b8949...).

## Contents
- pool-killed.txt: frozen pool, 36 killed mutant IDs (2090:7, 2156:6,
  2204:19, 2231:4 - matches the published replay verdicts).
- selection-10.txt: the sampled 10.
- out/<pr>/kill-<id>.log: per-sample replays, all "1/1 mutants
  killed", each with the mutant diff and selected tests.
- out/<pr>/survivor-<id>.log: specimen-driven killability proofs for
  the 4 original survivors (3x story.rb:777 via
  zz_independent_verification_is_gone_boundary_spec.rb; 1x
  settings_controller.rb:51 via
  zz_independent_verification_settings_no_rename_spec.rb; specimens
  in out/specimens/, temporary files, not app suite edits).
- out/<pr>/confirm-all*.log: whole-HEAD-suite confirmation attempts.
  2204 + 2156 first attempts FAILED at baseline: github_spec
  CGI.parse NoMethodError (env issue D-ENV-1, exit 5, no mutants
  started). cgi-denv1-trace.txt documents the before/after fix on
  the verifier's own ruby tree (stdlib removal-shim renamed aside so
  the Gemfile's cgi 0.5.1 resolves; LoadError side effect noted).
  2204/confirm-all-ex1.log (07:45:53, after the fix, EX-1 only):
  whole-suite map build in progress at log end - whole-HEAD
  confirmation NOT complete in this packet.
- out/cgi-denv1-trace.txt, out/DEVIATIONS.md.

## Publisher verification of this packet
- selection-10 is a strict subset of pool-killed (comm check, 0
  extras); every kill log's Replay line matches its filename ID.
- All 10 sample logs + 4 survivor logs show the killed verdict with
  diffs; 0 timeouts/errors/infra failures observed in the sample.
  QUALIFIED (main's audit, load-bearing): this is reproduction of the
  TOOL KILL VERDICT ONLY. The packet has no per-mutant report.json and
  no failure backtraces, so cause checks are NOT complete and no
  aggregate PASS is claimed.
- Fake-kill: zero "user_administration" occurrences in every packet
  file except DEVIATIONS.md naming the EX-1 pattern itself.
- UNVERIFIED CAUSE: the logs do NOT contain failing-test output (no
  RSpec failure bodies, no backtraces, no per-mutant JSON). The
  8-assertion / 2-mutation-induced-raise split is WORKER-REPORTED and
  UNVERIFIED. The body_raise operator on 2204:c48b2d39 and
  2231:a40b6c22 is NOT cause evidence. Per-sample cause awaits
  bundle-exec reruns with report JSON failure causes.
- UNVERIFIED ENVIRONMENT: every packet log warns "Gemfile.lock found
  but Bundler is not loaded: gems resolve to whatever is installed,
  not the lockfile's versions" and the actual invocation is absent
  from the logs. These runs are NOT lock-equivalent reproductions of
  the producer's pinned environment. The 4 survivor killability
  proofs carry the same bundle-context caveat: preserved as tool
  verdicts, pending verified bundle-exec reruns. The producer/fresh
  worker has been asked to rerun under bundle exec with report JSON
  failure causes, pinned identity, and the packet algorithm/seed
  embedded for repro.
- Killability proven != real-gap classification: the 4 survivor
  proofs used NEW specimen tests; classification as genuine test gaps
  requires the whole-HEAD existing-tests confirmation (EX-1 only),
  which was still running at packet time.
- Sample selection: the original 20261023 handoff specifies Ruby
  shuffle then sorted-unique on (scenario, id); this packet did not
  embed the algorithm/seed file, so the selection is not reproducible
  from the packet alone (requested from the worker).
- EX-2 event per worker ack (DEVIATIONS.md item 6): an EX-2
  github_spec exclusion was DRAFTED in config, STOPPED before any run
  used it, and reverted (07:44-07:45). Unapproved attempt, not a
  valid run; no skip authorized. Current scope remains EX-1 only.
  The confirm-all baseline failures above are the D-ENV-1 env issue
  (CGI shim), a separate matter from EX-1's app-red test - the
  earlier "CGI probe" framing was withdrawn by the worker as false;
  cgi-denv1-trace.txt is the actual trace.
- User-facing note: the "10 verified" claim stays internal until the
  raw independent audit is complete.
