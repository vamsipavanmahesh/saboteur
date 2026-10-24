# Chatwoot baseline - 2026-10-24 run (green)

Baseline: 3252 examples, 0 failures, 2 pending; exit 0; 10:15:29 to 11:01:54 IST, wall 2785s, peak RSS 653368 KB (2s sampler, sum of VmRSS over the rspec process tree).
Extra: 31 examples, 0 failures; exit 0; wall 11s.

Provenance: meta files received at 11:19 IST 2026-10-24; the full today's rspec log arrives with the checkpoint packet.
Note: reports/baseline/ and reports/baseline-extra/ (undated) and logs/baseline-rspec.log ("Finished in 3 minutes 25.3 seconds") are the 2026-10-23 22:07 attempt, kept immutable. Example counts (3252 baseline, 31 extra) match across both days; the timing lines do not - this directory is the 2026-10-24 record.

Map attempt 1 (11:17 IST) did not start mapping: the bundler RESOLVER phase was OOM-killed (cgroup memory.max=1944915968, events oom_kill=1, install phase never reached); raw diagnostic preserved at logs/oom-diagnostic-map1-20261024.txt. Recovery per the chatwoot D32 record: stop postgres/redis, standalone bundle install with max free RAM, restart and verify, then run the map with the lock satisfied; a second OOM stops for diagnosis (no loop). Recovery does not authorize broad dependency version updates.
