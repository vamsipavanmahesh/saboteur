# PR 2204 inclusive whole-suite confirmation (lobsters) - merger audit 2026-10-24 09:25 IST

Raw verifier packet (immutable, hashes in RAWS.sha256) + this derived audit. Verifier lane, worker-run; merger verified every number below by directly reading the attached report JSON and log.

## Verdict: QUALIFIED PARTIAL (row-level), with three open items carried below

Verified from raws:
- Command (log line 1, verbatim): `timeout 3000 bundle exec saboteur run --config config/saboteur-inclusive.rb --since 8f1b50061e5ef0b88ddbadc675395f7b5cf4eb76 --all --jobs 1 --baseline-passes 1 --max-duration 3600 --seed 1 --verbose --json .../report-confirm-all-inclusive.json`
- Whole suite, no EX-1: run warning "running the loaded suite unscoped: 861 examples in 104 spec files; 2 full passes"; config has no rspec exclusions (include app/**/*.rb only); targeted-verdicts.md: user_administration spec GREEN on this HEAD (5 examples 0 failures, 2026-10-24T02:58:46Z), so inclusion is valid (861 = 856 + 5).
- 1 subject (Story#is_gone?, app/models/story.rb), 22 mutants: 16 Killed (14 assertion, 2 crash), 0 Survived, 6 RuntimeError rejected kills. Exit 0. These exact counts are in the JSON per-mutant statuses and the log footer.
- The 6 rejected kills were rejected by the TOOL's own unchanged-method check, not by the verifier: each statusReason reads "killing test <spec> also fails with the method unchanged: ActiveRecord::RecordInvalid: Validation failed: Domain has already been taken" (5dd5baf1 search_spec[1:2]; 56ec2857, 69598274, 9786b8df submit_story_spec[1:10]; ac002c38 story_spec[1:27:2:3]; 906c7556 story_spec[1:27:2:2]). Not counted as killed. The three earlier scoped-run "survivors" (56ec2857, 69598274, 9786b8df) are inside this rejected set: they are UNRESOLVED, not survivors and not confirmed real gaps. The subset-ordering/pollution explanation remains a hypothesis, not reproduced.
- Fake-kill check (user protocol): no kill rests on user_administration_spec (0 covering entries for any mutant). The rejected class is the Domain-collision pollution above; the tool caught and excluded it.

## Open items (carried, none change the row-level 16/16-tested score if resolved adversely)
1. OPEN - accepted crash kill 21af923ed1980e24 has statusReason "crash: ActiveRecord::RecordInvalid", the SAME exception class as all 6 rejected kills. The tool's unchanged-method check passed it, but the class match under uncontrolled ordering pollution warrants the verifier's planned specimen PASS/KILL rerun before the per-mutant ledger treats it as settled. If it flips to rejected, the score stays 100% (15/15 tested).
2. OPEN - report JSON "complete": false despite exitCause "ok" and wrapper exit=0. Hypothesis (not verified): complete=false reflects the 6 unresolved rejected kills. Needs tool-source confirmation.
3. OPEN - timing: engine wall 490.26 s (baseline 36.0 + map 252.5 + mutants 193.3) vs observed file-to-file elapsed ~48 min (08:28:46 -> 09:16:52 IST). Cause unknown; no stall or performance claim is made anywhere in this packet.

## Disclosures retained
- Verifier lane runtime: saboteur 0.12.3 loaded from a pinned-source path checkout (6f87ccc98377bf0c23f3cf409006f0464c2aa67c, git clean), NOT the vendored built artifact; content byte-identical to the artifact per the merger's 09:22 artifact-vs-pin audit (238/238 files). Field-run lanes use the vendored artifact per the 06:46 instruction.
- Warnings retained: Landlock ABI 2 vs 3 (sandbox degrades to hazard guard + canary); debug-gem remote-console server thread and rack-mini-profiler thread alive at fork (children behavior depends on RUBY_DEBUG_FORK_MODE; unattended runs should drop RUBY_DEBUG_OPEN).
- Score line (100.0%, 16/16 tested, assertion 87.5% / crash 12.5%) covers TESTED mutants only; the 6 rejected kills are excluded from the denominator by the tool. This is a partial result toward the 15-row lobsters stage, not whole-plan completion.

## CORRECTION 09:49 IST (semantics, not numbers)
The 2204 inclusive run used `--since 8f1b5006... --all`: it executed ALL 861 TESTS but wrote NO whole-suite-map-v2 pointer. The tool's own 2156-run log states the rule ("survivors unconfirmed: no whole-suite coverage map" / "covering list is this run's selection only"). Consequence for this packet: its 6 rejected-kill UNRESOLVED mutants were never pointer-confirmable in this run; "whole suite" here means all-tests-executed, not whole-marked-pointer semantics. No number in this packet changes (0 survivors recorded; kills need no confirmation). The survivor-confirmation mechanism proof lives in pr2204-canary-c1/ (pointer present, confirmation engaged) and is unaffected. Also retracted: the merger's earlier remark that the producer lock's brakeman/matrix bumps do not undermine the c1 mechanism proof because the executed set is "capybara-free" - that impact is UNASSESSED, not established; the bumps stand as a disclosed environment deviation only.
