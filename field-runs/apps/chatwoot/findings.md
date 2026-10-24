# Chatwoot preparation findings

Application setup completed with recorded source-build and database-initialization deviations. This is not an unchanged setup flow and does not establish that saboteur install/map CI works. Tool versions and dependency constraints are in ENV.md.

The measured baseline covers the selected Community Edition models and services directories, not the entire application. Enterprise paths were stripped following the pinned FOSS workflow; the remaining pending enterprise-audit examples and their reasons are preserved in reports/baseline/pending_examples.json. Additional PR-related mailbox/job baseline evidence is separate, not silently added into the primary baseline. No baseline failures were excluded from either successful run.

An initial /usr/bin/time invocation failed because that executable was unavailable. logs/baseline-rspec.time preserves that failure. The successful baseline resource measurement instead used the supplied shell sampler and meta.env. This is environment friction, not a saboteur bug.

The sampler observes the RSpec parent and direct children only, at periodic intervals. It is not complete descendant-tree peak memory, excludes database/Redis services and may miss short peaks. Its elapsed wall time includes the polling loop tail and uses integer wall-clock seconds. RSpec's own example duration is a separate measure. Lobsters used a different peak-child-RSS method, so the memory figures must not be compared as equivalent costs.

Saboteur versioned runs, map cost, mutation results, parallelism, determinism, independent survivor triage and kill verification remain unknown. No Rails PR-gate conclusion is supported by these preparation baselines.
