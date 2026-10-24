# Verifier packet 3 - open crash kill 21af923ed1980e24 - merger audit: REAL KILL (2026-10-24 11:27 IST)

Question (user review item 3, 11:21 IST): is the accepted crash kill 21af923ed1980e24 (RecordInvalid, same exception class as the 6 rejected Domain-collision kills) a fake kill? Verdict from the attached raws: NO - REAL KILL. The 2204 row stands: 19 killed (18 assertion + this 1 crash), 3 survivors, no metric change.

Gate evidence (original PASS / mutant FAIL / isolated rerun, same full ID):
1. Original code, spec/models/search_spec.rb in isolation: 33 examples, 0 failures, exit=0 (isolation-original-search.log).
2. Mutant 21af923ed1980e24, same spec in isolation: 33 examples, 33 failures + 1 error outside examples, exit=1 (isolation-mutant-search.log). Every failure is ActiveRecord::RecordInvalid "Validation failed: Story is no longer accepting comments." raised at search_spec.rb:41 (comment-creating setup).
3. Engine isolated rerun (--id 21af923ed1980e24 --since 8f1b5006... --test spec/models/search_spec.rb --jobs 1): 1/1 killed, exit 0, 25.3s (rerun log + report JSON: status Killed, statusReason "crash: ActiveRecord::RecordInvalid", killedBy 33/33 test indices).

Cause attribution (from the report's own diff): boolean_logic on Story#is_gone? (story.rb:777) collapses `is_deleted? || (user.is_banned? && score < 0 && is_moderated == false)` to `is_deleted? || (is_moderated == false)`. Under the mutant, unmoderated fixture stories become "gone", so comment creation raises RecordInvalid in test setup. The failure is a direct consequence of the mutated predicate on the mutated tree only - the unchanged tree passes the same spec 33/0.

Why this differs from the 6 rejected Domain-collision kills (pr2204-confirm-all-inclusive): those failed on UNCHANGED code (pollution from parallel domain state) = environment, hence rejected. This kill never fails on unchanged code (receipt 1) and always fails on the mutated code with a mutation-derived message (receipts 2-3). Same exception class, different cause; class alone does not determine fake vs real.

Note: this mutant sits on the same statement (story.rb:777) as the 3 confirmed survivors; it exercises a different aspect (predicate collapse), which the suite detects through setup failure. No contradiction with the gap finding (boundary/literal aspects remain un pinned).
