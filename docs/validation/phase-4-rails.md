# Phase 4: a Rails app (rubyforgood/human-essentials)

Target: rubyforgood/human-essentials at d6f829046ee9696499f6781fc8f9e434d270a2be
(MIT licence), Rails 8.1, Postgres 16 in Docker, Ruby 3.4.3. Test env only,
no network from tests. Config: integration/configs/human-essentials.yml
(app/models and app/services; system specs excluded).

Scope: 136 files, 664 subjects, 4,202 candidate mutations.

## Baseline suite (system specs excluded), under script/watchdog

| run | examples | failed | pending | wall | peak RSS | leftovers |
|-----|----------|--------|---------|------|----------|-----------|
| 1   | 2,415    | 0      | 1       | 155.5 s | 816 MB | 0 |
| 2   | 2,415    | 0      | 1       | 153.4 s | 742 MB | 0 |
| 3   | 2,415    | 0      | 1       | 153.5 s | 730 MB | 0 |

Flaky tests: none. Every example had the same status in all three runs, so
nothing is excluded.

The app starts SimpleCov from its test environment. Saboteur now turns
SimpleCov.start into a no-op for the run (Boot.silence_simplecov), because it
needs Ruby's Coverage itself.
