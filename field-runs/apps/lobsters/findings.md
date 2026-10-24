# Lobsters findings (prose; computed numbers live in logs/ and reports/)

Pinned app SHA: 407536444934ac7d78f4ce1c18f228e3891a8663 (origin/main, 2026-10-23).
Setup required recorded deviations from the documented flow (see ENV.md); findings below were observed after those deviations. No app files modified.

## F-ENV-1: documented `sudo apt install libvips` is insufficient on Ubuntu 22.04
CONTRIBUTING.md says to install libvips via apt. Ubuntu 22.04 ships libvips 8.12.1; Rails 8.1
then refuses to boot: "libvips's unfuzzed operations are not safe to use with untrusted content...
requires libvips 8.13 or later and ruby-vips 2.2.1 or later." Verified twice in logs/bin-setup.log
(RETRY2). Worked around for this run with prebuilt libvips 8.18.7 (see ENV.md); the documented
instruction alone does not produce a bootable app on this common LTS. Environment/docs finding,
not necessarily an app bug.

## F-BASE-1 (CORRECTED 2026-10-24): spec/extras/github_spec.rb:14 failed because of the load path, not because of cgi 0.5.1
- Observed: spec/extras/github_spec.rb:14 failed repeatedly (3 runs) with NoMethodError: undefined method 'parse' for class CGI (logs/baseline-failures-recheck.log, logs/baseline-rspec.log). Those logs are kept unchanged as historical environment failures.
- RETRACTED: the earlier statement that cgi 0.5.1 no longer has CGI.parse, and the statement that extras/github.rb:21 (`CGI.parse(res)`) would raise at runtime on the required Ruby. Both are wrong. The locked cgi 0.5.1 gem (sha256 e93fcafc69b8a934fe1e6146121fa35430efa8b4a4047c4893764067036f18e9) defines CGI.parse at lib/cgi/core.rb:396.
- Cause: the published env.sh prepends Ruby's core library directories to RUBYLIB. That loaded Ruby 4's cgi.rb compatibility stub instead of the activated lock-pinned cgi gem, and the stub has no CGI.parse. The failure is an environment load-path artifact; it is not an application defect and no upstream defect claim stands.
- Correction control: env400.sh prepends the locked gem's lib directory before the core directories; no gem version or app file changed. Fresh controls with it are in reports/cgi-loadpath-recovery/ (2178 HEAD/BASE 842 examples / 0 failures each; 2158 HEAD/BASE 837 / 0 each; fresh database, seed 3). These are new controls, not replacements for earlier measurement artifacts.
- Impact on published rows: no affected row identified. spec/extras/github_spec.rb is the only spec that calls CGI.parse, extras/github.rb is outside the mutation scope (app/ and lib/), and a scan of published mutant report subject/statusReason/replacement fields and Github file paths found no CGI or Github matches. Residual caveat: every published row ran with the same RUBYLIB ordering, and whole-suite effects of one extra baseline-red spec are not established. This is not an exoneration of the 13 rows.
- reports/baseline_measurement.json known_failures lists this spec; read that entry as an environment load-path failure, not an application finding.

## F-BASE-2: spec/features/user_administration_spec.rb:39 "banning" observed failing repeatedly (3 runs; non-flakiness not proven)
- Command: bundle exec rspec spec/features/user_administration_spec.rb (also in full-suite baseline)
- Error: RSpec::Expectations::ExpectationNotMetError: Expected 0 to eq 1.
  Failing expectation: line 50 `expect(sent_emails.size).to eq(1)` - banning a user sends no
  notification email on the pinned tree.
- Context: pinned history includes 2026-10-21 commit e646f63a "restore transactional +
  notifications email; not yet mailing list mode"; the pinned tree appears mid-repair of the
  email subsystem. Not investigated further - root-cause triage is reserved for the independent
  independent triage per protocol.
- Observed failing in the original full-suite baseline plus 2 subsequent isolated reruns (3 observed runs total; same log). Repeated failures observed; 3 runs do not prove non-flakiness.

## Impact on downstream stages
- Neither failing spec overlaps the 5 selected PRs' spec files (comment/story/settings/home/search).
  F-BASE-1 and F-BASE-2 are baseline-red, explicitly named here with reasons. No exit code, map
  result, or replay result is adjusted for them; the observed baseline suite was not green.
  Any map or replay run that hits red (including these) is reported as a finding.
- F-ENV-1 means any environment rebuild must repeat the libvips 8.18.7 provision in ENV.md.

## F-ENV-2: PR #2053's head tree (2026-07-09) requires MySQL; documented setup cannot complete here
- Era check: all selected PR trees pre-2026-07-15 still used MySQL via the trilogy gem
  (pr2053 Gemfile:10 `gem "trilogy"`, DATABASE_URL mysql). The pinned main and later trees use
  app-compiled SQLite. The MySQL->SQLite migration landed between 2026-07-09 and 2026-07-15.
- trilogy 2.9.0 also needed OpenSSL headers (libssl-dev + multiarch include dir), provisioned
  locally per ENV.md and recorded in commands.sh section 9 - the gem then built fine.
- Blocker: documented bin/setup -> rails db:setup -> "Connection refused - trilogy_connect -
  unable to connect to 127.0.0.1:3306" (logs/pr2053-head-specs.log). No MySQL server exists in
  this no-sudo sandbox and none was provisioned (heavy, out of scope for the speed steer).
- Consequence: #2053 demoted to spare; #2143 substituted (nearest confirmed SQLite-era merged PR,
  ancestor of pin, story.rb + story_spec.rb). Recorded in prs/selected_prs.json.
