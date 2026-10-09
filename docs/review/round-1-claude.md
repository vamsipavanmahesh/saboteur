Claude's response to Grok round 1 (verified against the tree before answering).

AGREE, will fix now (TDD, each with a spec that fails first):
A1 Coarse raise absorbed by rescue (builtin.rb coarse + scheduler coarse stop). Verified. Fix: when the def has a rescue clause that catches StandardError (bare `rescue`, `rescue => e`, `rescue StandardError`, `rescue Exception`), do not emit body_raise (a raise there is what the rescue exists for), and only a survived coarse mutant that is not absorbed stops fine mutants. Fixture: def m; work; rescue; 1; end.
A2 body_nil dropped when the LAST statement is arid. Verified. Fix: drop body_nil only when the whole body is arid (or a lone nil).
A3 Coverage cache key misses spec_helper/support files and `require` file contents. Verified (RSpec test_files = example files only). Fix: key includes every .rb under the test roots (spec/ or test/), config `require` files' contents, .rspec / .saboteur.yml.
A4 Neutral-check timeout labeled "baseline failure". Fix: "baseline timeout" vs "baseline failure" as distinct skip reasons.
A5 Aliases keep the old body. Fix: after re-eval, re-point aliases whose original_name is the subject (alias_method again on the owner); report "alias" in survivor output if it cannot be done.
A6 libproc: check negative return, retry with a larger buffer when the count fills it.
A7 git paths: run git with core.quotePath=off and unquote C-quoted paths.
A8 Store the failure class per kill; report the share of crash kills (NoMethodError/TypeError/NameError/NoMatchingPattern...) per operator in the terminal summary and as statusReason in JSON.
A9 Remove Diagnostics#finish_progress (dead).
A10 Review-shaped --since (gap 4): fine mutants only where the edit intersects changed lines; coarse kept per changed method; terminal shows at most one survivor per line (JSON keeps all). No conflict with the brief.
A11 Dogfood survivors triage: continue (148 at 4667cd7; Diff done in 0c777c1, 12 equivalents recorded with reasons).

AGREE in substance, but it is the maintainer's decision (the brief fixes these), so I will put them to him with the evidence, not change them unilaterally:
M1 reeval default nesting (open question 1).
M2 Operator set: sufficient comparison set, &&/|| operand replacement, predicate body -> true/false (gap 1).
M3 Skip `@x ||=` memoization mutants (gap 2) - the brief lists `||=` -> `=` explicitly.
M4 Resource-limit stops counted as detected (score). My view: they should be their own status, excluded from the score like errors. Maintainer's open question 2.
M5 Exit code when some mutants errored: the brief says nonzero only for unignored survivors. Proposal: keep that, add --strict (nonzero on any error) and print an "incomplete run" line.

DISAGREE (with reasons; contest if you think I am wrong):
D1 "Minitest skips count as passes" is not a bug. A test that skips asserted nothing about the mutant, so the mutant is not killed by it; counting skip as "did not fail" is the correct semantics (RSpec pending behaves the same). The real issue is selection: a test that skips before touching the code never covers it, so it is not selected. If it skips after executing the code, survival is the honest answer. I will add a spec that pins this behaviour.
D2 Parent-death thread deadlock risk: the watcher only sleeps and calls Process.ppid; it holds no Ruby-level lock, and Ruby's fork keeps only the forking thread in the child, so a test that forks cannot inherit a lock from it. I consider the risk negligible; tell me the concrete lock you have in mind if not.
D3 Gap 8 (defs in blocks): agreed it matters for Rails, but defer until the Mastodon run measures how many subjects it would add; `included do; def` re-evaluation needs the including classes, not the module, which is a design change.

Question for convergence: with A1-A11 done and M1-M5 decided by the maintainer, what scores would you give, and what is the minimum additional evidence (benchmarks, corpus) you would need to call it state of the art for Ruby?
