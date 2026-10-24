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

## F-BASE-1: spec/extras/github_spec.rb:14 observed failing repeatedly on the pinned tree + required Ruby (3 runs; non-flakiness not proven)
- Command: bundle exec rspec spec/extras/github_spec.rb (also in full-suite baseline, logs/baseline-rspec.json)
- Error: NoMethodError: undefined method 'parse' for class CGI
- Cause verified: Ruby 4.0.9 (the version .ruby-version REQUIRES at this pin) ships cgi 0.5.1,
  where CGI.parse no longer exists (ruby -e 'require "cgi"; p CGI.respond_to?(:parse)' => false).
- Real code path affected: extras/github.rb:21 `ps = CGI.parse(res)` inside
  Github.token_and_user_from_code (GitHub account linking). The spec comment says it exists to
  prove CGI.parse is loaded. On the required Ruby this feature would raise at runtime.
- Observed failing in the original full-suite baseline plus 2 subsequent isolated reruns (3 observed runs total; logs/baseline-failures-recheck.log). Repeated failures observed; 3 runs do not prove non-flakiness.

## F-BASE-2: spec/features/user_administration_spec.rb:39 "banning" observed failing repeatedly (3 runs; non-flakiness not proven)
- Command: bundle exec rspec spec/features/user_administration_spec.rb (also in full-suite baseline)
- Error: RSpec::Expectations::ExpectationNotMetError: Expected 0 to eq 1.
  Failing expectation: line 50 `expect(sent_emails.size).to eq(1)` - banning a user sends no
  notification email on the pinned tree.
- Context: pinned history includes 2026-10-21 commit e646f63a "restore transactional +
  notifications email; not yet mailing list mode"; the pinned tree appears mid-repair of the
  email subsystem. Not investigated further - root-cause triage is reserved for the independent
  fresh-context triager per protocol.
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
