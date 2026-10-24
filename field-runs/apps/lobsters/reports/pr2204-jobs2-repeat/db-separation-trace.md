# DB separation observation trace (jobs2 instrumented repeat, PR #2204 tree)

Captured live 2026-10-24 IST by polling `ls db/test/` every 3s during reports/pr2204-jobs2-repeat.

- 07:29:36 repeat launched (bundle exec saboteur pr --since 8f1b50061e... --jobs 2)
- polls 07:29:39, 07:29:42, 07:29:45: only primary/cache/queue/rack_attack base files
- 07:29:48 poll: per-worker copies PRESENT: primary_saboteur2.sqlite3, cache_saboteur2.sqlite3, queue_saboteur2.sqlite3, rack_attack_saboteur2.sqlite3
- post-run (~07:30:2x, JOBS2REPEAT_EXIT=1): 0 *_saboteur* files remain (cleanup_workers dropped them)

Source mechanism (contract): lib/saboteur/frameworks/rails.rb worker_database() names extra workers' copies <db>_saboteur<N>.<ext>; prepare_workers copies per extra worker before start; cleanup_workers drops all copies after the run. Observation matches contract. Verdicts of repeat vs serial: 22/22 statuses identical.
