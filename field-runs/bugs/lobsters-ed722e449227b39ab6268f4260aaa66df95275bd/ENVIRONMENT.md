# Introducing-era environment assessment (commit b8cc0cef, 2026-06-19)

- Ruby: .ruby-version = 4.0.0 - MATCHES available ruby 4.0.0 tree. ELIGIBLE.
- DB: June-era CI (.github/workflows/check.yml at b8cc0cef) runs tests on MariaDB 10.11 via trilogy (DATABASE_URL trilogy://root:root@127.0.0.1/lobsters_dev). Committed db/schema.rb line 66 uses MySQL-only :unsigned; sqlite schema load fails ("Unknown key: :unsigned"). sqlite3 gem present in Gemfile but the era's tested DB is MariaDB. The current field-run stack (pin 40753644, Sept PR trees) is sqlite-only; box has no MariaDB server.
- Skip-rule assessment (user rule B2 "skip if needs a different DB"): introducing era needs MariaDB/trilogy, different from the available sqlite stack. Candidate SKIP (reason: different DB), UNLESS the explicit "start with 2204's bug" instruction is read to override; decision escalated to main/user 08:16.
- Setup work completed regardless (reusable if approved): June trees bug2204-intro-base (7037494e) + bug2204-intro (b8cc0cef) bundled green (ruby 4.0.0, saboteur 0.12.3 built gem via vendor/cache; trilogy built with local openssl headers - same pkgs/root pattern as libyaml/psych, recorded).
