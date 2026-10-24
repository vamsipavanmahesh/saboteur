# Saboteur Rails field report: complete recorded evidence

Updated October 24, 2026, 06:49 IST. This PDF contains the original nine-page report in full, followed by the Solidus timing analysis, environment and replay notes, PR selections and original baseline failures. It reports recorded work, not a completed field test.

## New Lobsters run: status at this snapshot

The original October 23-24 window remains historical. Its final paragraph says a verified release would be needed; the user's October 24 instruction supersedes that prerequisite. The new run uses a gem built from pinned main, not a 0.13.0 release. Lobsters must complete all stages and independent checks before Chatwoot begins. Solidus execution is out of scope. The latest three-hour run stops at 09:46:01 IST on October 24. Evidence belongs in field-runs/ inside saboteur; the separate repository push was cancelled.

Source SHA: `6f87ccc98377bf0c23f3cf409006f0464c2aa67c`. Gem version: `0.12.3`.

Built artifact SHA-256: `7f5b8949bce9bda19a584c079631d3b76ad37e700935285b550b7bb1c30689fa`.

Lobsters pin: `407536444934ac7d78f4ce1c18f228e3891a8663`.

| Command | Recorded result | Saboteur version / source SHA |
| --- | --- | --- |
| `bundle install --local` | Exit 0; 1.69 s; peak child RSS 75416 KiB. Raw measurement received. | 0.12.3 / `6f87ccc98377bf0c23f3cf409006f0464c2aa67c` |
| `bundle exec rails generate saboteur:install` | Exit 0; 4.15 s reported by execution record. Raw generator log and enriched measurement received. This 06:39:10 command preceded the installed-gem flow at 06:41; it belongs to the initial source-path flow, not proven built-artifact generator execution. | 0.12.3 / `6f87ccc98377bf0c23f3cf409006f0464c2aa67c` |
| `bundle exec saboteur doctor` | Exit 0; 6.42 s; RSS 304044 KiB in raw log. Material sandbox warning below. | 0.12.3 / `6f87ccc98377bf0c23f3cf409006f0464c2aa67c` |
| `bundle exec saboteur install` | Exit 0; 0.76 s; RSS 47200 KiB. Both workflow files already existed and were skipped. Idempotent check after generator, not a fresh-install control. | 0.12.3 / `6f87ccc98377bf0c23f3cf409006f0464c2aa67c` |
| Corrected full baseline | Exit 1; 41.93 s; RSS 463384 KiB. 913 examples, 1 failure: banning-email test. CGI green. | 0.12.3 / `6f87ccc98377bf0c23f3cf409006f0464c2aa67c` |
| Whole-suite map attempt 1 | BLOCKED. Exit 5; 49.66 s; peak child RSS 426384 KiB. Raw log received. Baseline check 1 failed; no mutants started. jobs=4. | 0.12.3 / `6f87ccc98377bf0c23f3cf409006f0464c2aa67c` |
| Post-fix narrow spec rerun | Exit 1; 8.35 s; RSS 308372 KiB; 7 examples, 1 failure. CGI green; banning-email test red. | 0.12.3 / `6f87ccc98377bf0c23f3cf409006f0464c2aa67c` |

The vendored gem's hash and runtime installed-gem load path/version were received. Source-to-built-to-installed payload comparison is not yet independently checked in this report. The initial source-path install was superseded and is not counted as built-gem execution. Registry installation was replaced with the main-built gem in vendor/cache, as the requested pin requires.

Doctor reports Landlock ABI 2, while ABI 3 is required to restrict truncate(). Children would use the hazard guard and canary only. Doctor did not run the baseline. This is a passed command with a safety limitation, not a compatibility-clean verdict. Generated configuration sets jobs=4; it is not a serial comparison control.

Map command launched at 06:42:44 IST: `bundle exec saboteur run --all --verbose`, with HTML/JSON output requested. The first map attempt returned exit 5 after 49.66 s because its baseline had the two known failures. No mutants or usable map cache were produced. The raw map and baseline-check logs confirm these results. Five PR mutation replays, serial/parallel comparison, determinism and fresh independent survivor/kill verification remain unfinished. No scores or empty-success triage results are inferred.

A fresh narrow rerun of the two known failing Lobsters spec files recorded 7 examples, 2 failures, exit 1, 7.56 s. This is not a new 913-example baseline. The CGI investigation now attributes that failure to our RUBYLIB layout shadowing the installed cgi gem with Ruby's stdlib shim. CGI.parse exists in cgi 0.5.1; the earlier removal claim in the historical report is wrong. The sentinel spec failed before the application call site executed. The upstream failure class was fixed in issue #1845 / PR #1846 in January. No new issue is warranted on this evidence. Local correction is now confirmed by before/after probes and the narrow rerun below. The corrected full baseline finished: 913 examples, 1 failure, exit 1, 41.93 s; only the banning-email test remains red. D-ENV-1: the stdlib cgi.rb shim and cgi/ directory were renamed aside in both writable Ruby trees. RUBYLIB remains required for the relocated runtime. This is an explicit environment deviation, not an app/spec edit; bare require "cgi" outside bundler may now fail. The post-fix probe loads cgi-0.5.1 from the gem and reports PARSE=true. The two-file rerun records 7 examples, 1 failure, exit 1, 8.35 s. Excluding spec/features/user_administration_spec.rb has been proposed to the user but is NOT approved at this snapshot. No exclusion is counted. See the full investigation appendix, including a conditional standby draft that must not be filed unless the failure persists on a corrected runtime.

Historical PR selections below are not a qualified new replay set. The new scope requires merges strictly after July 15, 2026, with base=merge parent and head=merge commit; July 15 PR #2143 does not satisfy that date rule. The execution report replaces #2143 with #2182, merged September 14: merge `afd505e45084f7c9fd504ae8968886eee102c961`, parent `e5fda5974779549267ac25fdf4855fdd0cf0101b`. The other four merge-parent identities were reported checked; source audit artifacts are not yet included here. Literal `saboteur install` now has an actual record, but both workflow files already existed from the earlier generator and were skipped. This order cannot prove fresh unchanged install behavior.

Required-input rule: if a release, SHA, credentials or decision needed to reach the goal is missing, stop within 15 minutes and ask. Do not spend a timebox on preparation that cannot reach the goal.

Rule change completed through normal checks: PR #1342 merged as `42d24b2e04d3430b7f07eeadfb82396557398b53`. https://github.com/vamsipavanmahesh/saboteur/pull/1342. The field-run pin remains unchanged at `6f87ccc98377bf0c23f3cf409006f0464c2aa67c`.

The appended historical findings are retained verbatim for provenance, but their CGI attribution is superseded by the correction above and the investigation appendix. Measurement records were enriched after execution with source identity/status/evidence references; original numeric values and raw originals are retained.


# Original stopped-window report (historical)

# Saboteur Rails field report

Generated from the evidence files by script/summarize.rb. Missing measurements remain unknown. No conclusion extends beyond the measured stages.

## App summary

| App | Shape | Tracked Ruby files | Tracked spec files | Baseline (s) | Map (s) |
| --- | --- | --- | --- | --- | --- |
| chatwoot | large Postgres and Redis Rails app | 2957 | 1014 | 213 | unknown |
| lobsters | mid-size Rails app | 488 | 109 | 35.345 | unknown |
| solidus | Rails engine / multi-gem repository | 2112 | 822 | 1542 | unknown |

## chatwoot

Source: https://github.com/chatwoot/chatwoot at `7fe41fe03731fc2f5b1841b84351386962d2fd05`.

### Stage status

| Stage | Status | Reason | Evidence |
| --- | --- | --- | --- |
| environment | done | toolchain source-built (documented deviation, no sudo available); app deps installed; pg+redis up; schema loaded; smoke spec green | apps/chatwoot/ENV.md, apps/chatwoot/commands.sh |
| baseline | done | 3252 examples 0 failures 2 pending (enterprise-audit pending markers) exit 0, 213s; extra baseline 31/0/0 exit 0 for out-of-scope PR specs | apps/chatwoot/reports/baseline/measurement.json, apps/chatwoot/reports/baseline-extra/measurement.json, apps/chatwoot/logs/baseline-rspec.json, apps/chatwoot/logs/baseline-extra-rspec.json, apps/chatwoot/reports/baseline/pending_examples.json |
| documented_flow | not_done | Not started before the four-hour stop: verified saboteur 0.13.0 release identity was unavailable. Preparation controls are separate evidence, not a substitute. |  |
| map | not_done | Not started before the four-hour stop: verified saboteur 0.13.0 release identity was unavailable. Preparation controls are separate evidence, not a substitute. |  |
| pr_replays | not_done | Not started before the four-hour stop: verified saboteur 0.13.0 release identity was unavailable. Preparation controls are separate evidence, not a substitute. | apps/chatwoot/selected_prs.json |
| parallelism | not_done | Not started before the four-hour stop: verified saboteur 0.13.0 release identity was unavailable. Preparation controls are separate evidence, not a substitute. |  |
| determinism | not_done | Not started before the four-hour stop: verified saboteur 0.13.0 release identity was unavailable. Preparation controls are separate evidence, not a substitute. |  |
| triage | not_done | Not started: no versioned mutation reports exist to sample or independently verify. Findings unknown, not zero. |  |
| kills | not_done | Not started: no versioned mutation reports exist to sample or independently verify. Findings unknown, not zero. |  |

### Runs and resource cost

| Scenario | Kind | Status | Version | Saboteur SHA | Base | Head | Wall (s) | Peak RSS (KiB) | Exit |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| baseline | baseline | done | unknown | unknown | 7fe41fe03731fc2f5b1841b84351386962d2fd05 | unknown | 213 | 628840 | 0 |
| baseline-extra | baseline | done | unknown | unknown | 7fe41fe03731fc2f5b1841b84351386962d2fd05 | unknown | 8 | unknown | 0 |

### Baseline example results

| Examples | Failures | Pending | Errors outside examples |
| --- | --- | --- | --- |
| 3252 | 0 | 2 | 0 |


### Additional baseline results

| Scenario | Examples | Failures | Pending | Errors outside examples | Wall (s) |
| --- | --- | --- | --- | --- | --- |
| baseline-extra | 31 | 0 | 0 | 0 | 8 |

### Per-PR raw results

| Scenario | PR | Mutants | Killed | Survived | Timeout | Errors | Other | Score |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |

### Survivor triage counts

| Classification | Count |
| --- | --- |
| unknown | unknown |

### Kill causes

| Cause | Count |
| --- | --- |
| unknown | unknown |

Fake kills: unknown.

### False survivors

| Scenario | ID | Location | Evidence |
| --- | --- | --- | --- |
| unknown | unknown | unknown | unknown |

### Parallel and determinism verdict comparisons

| Scenario | Reference | Reference-only rows | Compared-only rows | Diff evidence |
| --- | --- | --- | --- | --- |
| unknown | unknown | unknown | unknown | unknown |

### App findings

# Chatwoot preparation findings

Application setup completed with recorded source-build and database-initialization deviations. This is not an unchanged setup flow and does not establish that saboteur install/map CI works. Tool versions and dependency constraints are in ENV.md.

The measured baseline covers the selected Community Edition models and services directories, not the entire application. Enterprise paths were stripped following the pinned FOSS workflow; the remaining pending enterprise-audit examples and their reasons are preserved in reports/baseline/pending_examples.json. Additional PR-related mailbox/job baseline evidence is separate, not silently added into the primary baseline. No baseline failures were excluded from either successful run.

An initial /usr/bin/time invocation failed because that executable was unavailable. logs/baseline-rspec.time preserves that failure. The successful baseline resource measurement instead used the supplied shell sampler and meta.env. This is environment friction, not a saboteur bug.

The sampler observes the RSpec parent and direct children only, at periodic intervals. It is not complete descendant-tree peak memory, excludes database/Redis services and may miss short peaks. Its elapsed wall time includes the polling loop tail and uses integer wall-clock seconds. RSpec's own example duration is a separate measure. Lobsters used a different peak-child-RSS method, so the memory figures must not be compared as equivalent costs.

Saboteur versioned runs, map cost, mutation results, parallelism, determinism, independent survivor triage and kill verification remain unknown. No Rails PR-gate conclusion is supported by these preparation baselines.


## lobsters

Source: https://github.com/lobsters/lobsters at `407536444934ac7d78f4ce1c18f228e3891a8663`.

### Stage status

| Stage | Status | Reason | Evidence |
| --- | --- | --- | --- |
| environment | done | bin/setup exit 0 only after recorded deviations (libvips 8.18.7 prebuilt, libyaml headers); documented flow was blocked at both points - not completed unchanged | logs/bin-setup.log, ENV.md |
| baseline | done | 913 examples, 2 pre-existing failures observed (F-BASE-1, F-BASE-2; each seen failing in 3 runs, non-flakiness not proven), exit 1, wall 35.3s | logs/baseline-rspec.json, reports/baseline/measurement.json, findings.md |
| documented_flow | not_done | Not started before the four-hour stop: verified saboteur 0.13.0 release identity was unavailable. Preparation controls are separate evidence, not a substitute. |  |
| map | not_done | Not started before the four-hour stop: verified saboteur 0.13.0 release identity was unavailable. Preparation controls are separate evidence, not a substitute. |  |
| pr_replays | not_done | Not started before the four-hour stop: verified saboteur 0.13.0 release identity was unavailable. Preparation controls are separate evidence, not a substitute. | prs/selected_prs.json, reports/pr2231-head-specs/measurement.json, reports/pr2204-head-specs/measurement.json, reports/pr2156-head-specs/measurement.json, reports/pr2090-head-specs/measurement.json, reports/pr2143-head-specs/measurement.json, reports/pr2231-base-specs/measurement.json, reports/pr2204-base-specs/measurement.json, reports/pr2156-base-specs/measurement.json, reports/pr2090-base-specs/measurement.json, reports/pr2143-base-specs/measurement.json |
| parallelism | not_done | Not started before the four-hour stop: verified saboteur 0.13.0 release identity was unavailable. Preparation controls are separate evidence, not a substitute. |  |
| determinism | not_done | Not started before the four-hour stop: verified saboteur 0.13.0 release identity was unavailable. Preparation controls are separate evidence, not a substitute. | logs/baseline-failures-recheck.log |
| triage | not_done | Not started: no versioned mutation reports exist to sample or independently verify. Findings unknown, not zero. |  |
| kills | not_done | Not started: no versioned mutation reports exist to sample or independently verify. Findings unknown, not zero. |  |

### Runs and resource cost

| Scenario | Kind | Status | Version | Saboteur SHA | Base | Head | Wall (s) | Peak RSS (KiB) | Exit |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| baseline | baseline | done | unknown | unknown | 407536444934ac7d78f4ce1c18f228e3891a8663 | unknown | 35.345 | 454056 | 1 |
| pr2090-base-specs | verification | done | unknown | unknown | 81ba649e1a667afddd1c780d0aeb37bad37ac308 | 87e1e318fc7cc914646605c34dae39ff4d28ef34 | 8.453 | 312268 | 0 |
| pr2090-head-specs | verification | done | unknown | unknown | 81ba649e1a667afddd1c780d0aeb37bad37ac308 | 87e1e318fc7cc914646605c34dae39ff4d28ef34 | 8.541 | 318272 | 0 |
| pr2143-base-specs | verification | done | unknown | unknown | e72cf85f041cfa82157173e0af82bce693e5c9d0 | 81ba649e1a667afddd1c780d0aeb37bad37ac308 | 9.219 | 327968 | 0 |
| pr2143-head-specs | verification | done | unknown | unknown | e72cf85f041cfa82157173e0af82bce693e5c9d0 | 81ba649e1a667afddd1c780d0aeb37bad37ac308 | 9.463 | 328388 | 0 |
| pr2156-base-specs | verification | partly | unknown | unknown | 9a773eac0b49fd86b16585ad503de9a51919c496 | d9998c2555317db7b3cb9a159ef7878ff993ab78 | 0.361 | 41152 | 1 |
| pr2156-head-specs | verification | done | unknown | unknown | 9a773eac0b49fd86b16585ad503de9a51919c496 | d9998c2555317db7b3cb9a159ef7878ff993ab78 | 5.81 | 290924 | 0 |
| pr2204-base-specs | verification | done | unknown | unknown | 8f1b50061e5ef0b88ddbadc675395f7b5cf4eb76 | ed722e449227b39ab6268f4260aaa66df95275bd | 8.701 | 356552 | 0 |
| pr2204-head-specs | verification | done | unknown | unknown | 8f1b50061e5ef0b88ddbadc675395f7b5cf4eb76 | ed722e449227b39ab6268f4260aaa66df95275bd | 9.146 | 344936 | 0 |
| pr2231-base-specs | verification | done | unknown | unknown | 372345a2cca5ed8e5d3376dcdc7e0a33e7f4f17c | 9fd8f5fca9b5f93a465a079cd0847b17b2acebe8 | 8.056 | 341092 | 0 |
| pr2231-head-specs | verification | done | unknown | unknown | 372345a2cca5ed8e5d3376dcdc7e0a33e7f4f17c | 9fd8f5fca9b5f93a465a079cd0847b17b2acebe8 | 8.498 | 314800 | 0 |

### Baseline example results

| Examples | Failures | Pending | Errors outside examples |
| --- | --- | --- | --- |
| 913 | 2 | 0 | 0 |


### Per-PR raw results

| Scenario | PR | Mutants | Killed | Survived | Timeout | Errors | Other | Score |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |

### Survivor triage counts

| Classification | Count |
| --- | --- |
| unknown | unknown |

### Kill causes

| Cause | Count |
| --- | --- |
| unknown | unknown |

Fake kills: unknown.

### False survivors

| Scenario | ID | Location | Evidence |
| --- | --- | --- | --- |
| unknown | unknown | unknown | unknown |

### Parallel and determinism verdict comparisons

| Scenario | Reference | Reference-only rows | Compared-only rows | Diff evidence |
| --- | --- | --- | --- | --- |
| unknown | unknown | unknown | unknown | unknown |

### App findings

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


## solidus

Source: https://github.com/solidusio/solidus at `07d5aff446586f6ab8ca024e2d8d08ee3e0463d8`.

### Stage status

| Stage | Status | Reason | Evidence |
| --- | --- | --- | --- |
| environment | done | unknown | apps/solidus/ENV.md, apps/solidus/logs/env-bundle-install.log, apps/solidus/logs/env-smoke.log |
| baseline | done | Measured full core baseline exits 1; pre-existing failures preserved in raw JSON and baseline-red-candidates.json. No mutation run or exclusion has been applied. | apps/solidus/logs/baseline-rspec.json, apps/solidus/reports/baseline/measurement.json, apps/solidus/reports/baseline/stdout+stderr.log, apps/solidus/logs/baseline-failures-recheck.log |
| documented_flow | not_done | Not started before the four-hour stop: verified saboteur 0.13.0 release identity was unavailable. Preparation controls are separate evidence, not a substitute. |  |
| map | not_done | Not started before the four-hour stop: verified saboteur 0.13.0 release identity was unavailable. Preparation controls are separate evidence, not a substitute. |  |
| pr_replays | not_done | Not started before the four-hour stop: verified saboteur 0.13.0 release identity was unavailable. Preparation controls are separate evidence, not a substitute. | apps/solidus/selection.csv |
| parallelism | not_done | Not started before the four-hour stop: verified saboteur 0.13.0 release identity was unavailable. Preparation controls are separate evidence, not a substitute. |  |
| determinism | not_done | Not started before the four-hour stop: verified saboteur 0.13.0 release identity was unavailable. Preparation controls are separate evidence, not a substitute. |  |
| triage | not_done | Not started: no versioned mutation reports exist to sample or independently verify. Findings unknown, not zero. |  |
| kills | not_done | Not started: no versioned mutation reports exist to sample or independently verify. Findings unknown, not zero. |  |

### Runs and resource cost

| Scenario | Kind | Status | Version | Saboteur SHA | Base | Head | Wall (s) | Peak RSS (KiB) | Exit |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| baseline | baseline | done | unknown | unknown | 07d5aff446586f6ab8ca024e2d8d08ee3e0463d8 | 07d5aff446586f6ab8ca024e2d8d08ee3e0463d8 | 1542 | 408468 | 1 |
| pr6677-base-scope | baseline | done | unknown | unknown | 198c66c2f36fae2aab622851e2945cb66ce9b44b | 198c66c2f36fae2aab622851e2945cb66ce9b44b | 27 | 213468 | 0 |
| pr6677-head-scope | baseline | done | unknown | unknown | 4dd53128473a4e0c7b7fdbb6d152e35a5ca7bb1b | 4dd53128473a4e0c7b7fdbb6d152e35a5ca7bb1b | 26 | 213528 | 0 |
| pr6691-base-scope | baseline | done | unknown | unknown | 7c1842d9099d76713b4d2a69001eac914a5f16d3 | 7c1842d9099d76713b4d2a69001eac914a5f16d3 | 27 | 212648 | 0 |
| pr6691-head-scope | baseline | done | unknown | unknown | 1514f27fc7b257ab1ae5bab5a3646a04f256b06a | 1514f27fc7b257ab1ae5bab5a3646a04f256b06a | 26 | 213632 | 0 |
| pr6692-base-scope | baseline | done | unknown | unknown | 78fb02ba19a443a6648aa870634700eb2c1a0a94 | 78fb02ba19a443a6648aa870634700eb2c1a0a94 | 24 | 213544 | 0 |
| pr6692-head-scope | baseline | done | unknown | unknown | c27efd40c184eba0c758ecc9429cf23551000f5f | c27efd40c184eba0c758ecc9429cf23551000f5f | 25 | 218320 | 0 |
| pr6697-base-scope | baseline | done | unknown | unknown | 5b47ff22b600011f369e8da0de60bfe60bb27039 | 5b47ff22b600011f369e8da0de60bfe60bb27039 | 751 | 212940 | 0 |
| pr6697-head-scope | baseline | done | unknown | unknown | 8950d6cc6b4d79c65b8a58172e60453d4d5e1d95 | 8950d6cc6b4d79c65b8a58172e60453d4d5e1d95 | 25 | 213280 | 0 |
| pr6701-base-scope | baseline | done | unknown | unknown | 5158ea6d0ebf63d29acce4ae9bc8332d59e2c321 | 5158ea6d0ebf63d29acce4ae9bc8332d59e2c321 | 25 | 212196 | 0 |
| pr6701-head-scope | baseline | done | unknown | unknown | 5b47ff22b600011f369e8da0de60bfe60bb27039 | 5b47ff22b600011f369e8da0de60bfe60bb27039 | 457 | 212968 | 0 |

### Baseline example results

| Examples | Failures | Pending | Errors outside examples |
| --- | --- | --- | --- |
| 4485 | 8 | 0 | 0 |


### Additional baseline results

| Scenario | Examples | Failures | Pending | Errors outside examples | Wall (s) |
| --- | --- | --- | --- | --- | --- |
| pr6677-base-scope | 233 | 0 | 0 | 0 | 27 |
| pr6677-head-scope | 233 | 0 | 0 | 0 | 26 |
| pr6691-base-scope | 233 | 0 | 0 | 0 | 27 |
| pr6691-head-scope | 239 | 0 | 0 | 0 | 26 |
| pr6692-base-scope | 220 | 0 | 0 | 0 | 24 |
| pr6692-head-scope | 224 | 0 | 0 | 0 | 25 |
| pr6697-base-scope | 226 | 0 | 0 | 0 | 751 |
| pr6697-head-scope | 233 | 0 | 0 | 0 | 25 |
| pr6701-base-scope | 224 | 0 | 0 | 0 | 25 |
| pr6701-head-scope | 226 | 0 | 0 | 0 | 457 |

### Per-PR raw results

| Scenario | PR | Mutants | Killed | Survived | Timeout | Errors | Other | Score |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |

### Survivor triage counts

| Classification | Count |
| --- | --- |
| unknown | unknown |

### Kill causes

| Cause | Count |
| --- | --- |
| unknown | unknown |

Fake kills: unknown.

### False survivors

| Scenario | ID | Location | Evidence |
| --- | --- | --- | --- |
| unknown | unknown | unknown | unknown |

### Parallel and determinism verdict comparisons

| Scenario | Reference | Reference-only rows | Compared-only rows | Diff evidence |
| --- | --- | --- | --- | --- |
| unknown | unknown | unknown | unknown | unknown |

### App findings

# Solidus findings (prose; all numbers recomputable from reports/ and logs/)

## Baseline (pin 07d5aff4, whole core suite)
4485 examples, 8 failures, 0 pending, exit 1, RSpec example duration 1536.850863559s; externally measured elapsed wall 1542s including wrapper, peak RSS ~399MB (1s sampled). Seed 49450.

## Baseline-red examples: candidates for explicit later exclusions
The raw baseline failures are in image-variant processing. Exact IDs and original exceptions are retained in baseline-red-candidates.json; no mutation-run exclusion has yet been applied. Future narrow replay scope is recorded separately:
- spec/models/spree/image_spec.rb[1:5:3] returns attachment url
- spec/models/spree/image_spec.rb[1:5:4] computes attachment width
- spec/models/spree/image_spec.rb[1:5:5] computes attachment height
- spec/models/spree/concerns/active_storage_adapter/attachment_spec.rb[1:1:1..5] (5 #variant examples)

Reason (verified, logs/baseline-failures-recheck.log):
- Isolated rerun of the two files, default env: 19 examples, 8 failures - same 8 (NoMethodError "undefined method 'new' for nil" at core/app/models/concerns/spree/active_storage_adapter/attachment.rb:38). Repeated failures are recorded in the full baseline and isolated-run logs; the log includes partial earlier reruns as well as later detailed output. These observations do not prove non-flakiness. Baseline width/height errors are expectations of 1 receiving nil, while other baseline failures report undefined new for nil.
- Diagnosis (not established as the sole cause under the unsupported relocated runtime): core/lib/spree/testing_support/dummy_app.rb:140 defaults active_storage.variant_processor to :vips; the sandbox has no system libvips, so the vips transformer lookup yields nil and `.new` is called on nil. Solidus CI installs libvips; the README core-suite instructions do not mention this dependency (documented-flow gap F-ENV-1).
- The app's own escape hatch (ACTIVE_STORAGE_VARIANT_PROCESSOR=mini_magick, same file:140) does NOT clear them: 19 examples, 6 failures, different error (ActiveStorage UnsupportedImageProcessingMethod: saver - Solidus passes a vips-only `saver:` transformation). Recorded as fact; not used as a workaround.

## Status by stage
environment done; baseline done (exit 1, baseline-red candidates above); documented_flow/map/pr_replays/parallelism/determinism not_done pending verified saboteur 0.13.0 SHA; triage/kills assigned to independent triage.



## Bounded outcome

The app execution window ran from October 23 at 21:39 IST to October 24 at 01:39 IST, including release waiting. Work stopped at the bound. Preparation baselines and selected-PR direct-spec controls are recorded; none is a saboteur mutation run.

No verified saboteur 0.13.0 release or source SHA was supplied during the window. Release publication remained held. The version, map runtime, per-PR mutation counts and scores, parallel verdict agreement, determinism, survivor classifications and kill causes are unknown. No conclusion that saboteur works as a Rails PR gate is supported.

### Status by stage

Application environment preparation and baseline measurements completed with recorded limitations and, on some apps, baseline failures. The requested saboteur install/documented whole-suite-map flow, map build, PR replays, parallel replay and determinism runs were not started. Direct-spec prechecks do not substitute for whole-suite maps or mutation runs. Missing direct specs on some historical bases do not make the entire base suite inapplicable.

Independent mutation triage and kill verification could not start without mutation reports. No empty selection, triage CSV, kill CSV or fake success diff was synthesized. Unknown findings are not zero findings.

### Runtime and resource limits

Baseline elapsed time is distinct from RSpec example duration. Published memory values use different methods and are not directly comparable: Lobsters records peak child RSS, while Chatwoot and Solidus sample a parent and direct children. Database-service and whole-machine memory cost were not measured. Wrapper exit limitations and unsupported runtime/setup deviations remain documented under each app.

### Crashes, contradictions and issues

Saboteur crashes, hangs, exit 70 and contradictory mutation output remain unknown because saboteur did not run. No saboteur field-test bug issue was filed without evidence. App baseline failures, failed setup attempts, missing historical direct specs and evidence-wrapper failures are preserved with their logs; they were not silently attributed to saboteur.

### Next decision

This bounded attempt is stopped, not automatically resumed. A new execution window after a verified release would be needed to complete the unstarted stages and independent verification. No additional run or infrastructure commitment is implied by this report.



# Solidus scoped-run outliers: existing evidence review

Reviewed October 24, 2026. No new Solidus run was performed.

Both outliers ran tree `5b47ff22b600011f369e8da0de60bfe60bb27039` with the same recorded spec scope. They are direct-spec controls, not saboteur mutation runs.

| Recorded run | Seed | Examples / failures | External wall | RSpec duration |
| --- | --- | --- | --- | --- |
| pr6697-base-scope | 30913 | 226 / 0 | 751 s | 745.991 s |
| pr6701-head-scope | 1995 | 226 / 0 | 457 s | 451.032 s |

A single passing example accounts for most of each long run. The same examples were fast in the other recorded run of that identical tree:

| Example ID | pr6697-base-scope | pr6701-head-scope |
| --- | --- | --- |
| `./spec/models/spree/stock/availability_validator_spec.rb[1:3:1:1]` | 725.542 s, passed | 0.110 s, passed |
| `./spec/models/spree/stock/simple_coordinator_spec.rb[1:1:8:1]` | 0.120 s, passed | 431.237 s, passed |

The long durations are recorded inside RSpec, rather than explained by the roughly 5-6 s difference between suite duration and external wall. Two separate examples inflated in the two runs. This pair does not establish a repeatable slow path, rule out an order-dependent slow path, or prove a host-load explanation.

Cause remains unknown. The earlier suggestion that PR #6697's change explained the outliers is withdrawn. These records contain no CPU/wait/GC trace that would distinguish scheduling delays, I/O or runtime pauses from application behavior. No speed or performance-fix conclusion follows from them.

## Evidence

- `apps/solidus/logs/pr6697-base-scope-rspec.json`
- `apps/solidus/logs/pr6701-head-scope-rspec.json`
- `apps/solidus/reports/pr6697-base-scope/measurement.json`
- `apps/solidus/reports/pr6701-head-scope/measurement.json`

The evidence belongs to the original stopped preparation window. It does not advance the new sequential Lobsters-first mutation run.


# Lobsters: full environment and replay notes

Historical preparation-window records. Release-wait statements below describe that window, not the new main-pinned run.


# Lobsters environment (field-run app environment)

- App: https://github.com/lobsters/lobsters
- Pinned SHA: 407536444934ac7d78f4ce1c18f228e3891a8663 ("bump for Ruby joining this week's CVE-a-thon", 2026-10-23 10:06:27 -0500, = origin/main HEAD at qualification)
- Qualification source: 488 tracked Ruby files, 109 *_spec.rb files, Rails 8.1.3.1 + rspec-rails 8.0.2, SQLite (app-compiled), Ruby 4.0.9 per .ruby-version
- Machine: Linux x86_64 sandbox container, Ubuntu 22.04.5 LTS (jammy), 2 CPUs, 1.9 GB RAM, no sudo, no paid infrastructure
- Timebox: 4h from 2026-10-23 21:39 IST (prep start); saboteur 0.13.0 measurements held until release SHA verified by main

## Documented setup (CONTRIBUTING.md "Setting up your environment") - NOT completed unchanged

The documented flow was BLOCKED at two points on this machine and only completed after the
recorded deviations below. The final successful setup is therefore "documented flow + recorded
deviations", not the documented flow verbatim.

1. "Install the Ruby version specified in .ruby-version" = 4.0.9.
   No sudo/apt possible; used the official ruby-builder prebuilt of the EXACT documented version:
   https://github.com/ruby/ruby-builder/releases/download/ruby-4.0.9/ruby-4.0.9-ubuntu-22.04-x64.tar.gz
   -> ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-linux], RubyGems/Bundler 4.0.20, OpenSSL 3.0.2.
   bin/* shebangs repointed to /usr/bin/env ruby (tarball targets a GitHub-hosted-toolcache path).
2. "Install libvips" (doc command: sudo apt install libvips).
   FINDING F-ENV-1: Ubuntu 22.04's packaged libvips is 8.12.1; Rails 8.1 refuses to boot with it
   ("libvips's unfuzzed operations are not safe... requires libvips 8.13 or later"). So the documented
   apt command is insufficient for this app on Ubuntu 22.04. Recorded as an environment finding.
   Resolution used (explicitly documented, not silent): prebuilt libvips 8.18.7 from sharp's official
   @img/sharp-libvips-linux-x64 1.3.4 npm tarball (lib/libvips-cpp.so.8.18.7 symlinked as libvips.so.42),
   verified loaded and reporting 8.18.7 via ruby FFI.
   (An intermediate step also apt-extracted jammy libvips42 8.12.1 + deps locally; superseded by 8.18.7.)
3. Missing system headers for native gems (no sudo): psych 5.3.1 needs yaml.h.
   Resolved by apt-get download libyaml-dev + libyaml-0-2, extracted locally, and
   `bundle config set --local build.psych --with-libyaml-include=... --with-libyaml-lib=...`.
   The app's own .bundle/config sqlite3 build flags were preserved unchanged.
4. `bin/setup` (idempotent by design) run 3 times: attempt 1 failed on psych/libyaml headers,
   attempt 2 failed on the libvips>=8.13 requirement (F-ENV-1), attempt 3 EXIT_CODE=0 at
   2026-10-23T21:50:59+05:30 after the recorded deviations above. Full log: logs/bin-setup.log.
   It created db/development/*.sqlite3 and db/test/*.sqlite3 and compiled sqlite3 with the repo's flags.

## Environment variables (~/field-runs/env.sh, sourced for every command)

- PATH: ruby-4.0.9/bin + its GEM_HOME/bin, then system
- LD_LIBRARY_PATH: ruby lib, sharp-libvips lib dir, apt-extracted lib dir
- RUBYLIB / GEM_HOME / GEM_PATH: ruby-4.0.9 tree (tarball prefix is not writable /opt)
- PKG_CONFIG_PATH / CPATH / LIBRARY_PATH: apt-extracted headers (libyaml) for native builds

## Not done (documented steps intentionally skipped)

- `rails credentials:edit`: not needed to run the test suite; no external-service keys used.
- `rails fake_data`: dev-sample data; not needed for RSpec baseline.
- No changes to app code, Gemfile, .bundle/config app flags, or any upstream file. No upstream PRs/issues filed
  (CONTRIBUTING forbids LLM-written code contributions; this run is local verification only).


# Replaying the Lobsters preparation

This packet preserves raw evidence from the original working directory. It has not been rerun from the published field-runs/ directory. commands.sh is a grouped replay recipe containing the recorded commands, not a literal shell record. The actual setup attempt chronology is in logs/bin-setup.log; failures are not hidden by the later successful provisioning.

From the saboteur repository root, place the included helpers at the historical paths before using commands.sh:

```sh
mkdir -p "$HOME/field-runs"
cp field-runs/apps/lobsters/env.sh "$HOME/field-runs/env.sh"
cp field-runs/apps/lobsters/runmeasured.py "$HOME/field-runs/runmeasured.py"
mkdir -p "$HOME/field-runs/saboteur-field-runs/apps/lobsters/logs"
mkdir -p "$HOME/field-runs/saboteur-field-runs/apps/lobsters/reports/baseline"
```

These output directories deliberately reproduce the historical EVIDENCE_DIR in env.sh. They do not create or require a separate GitHub repository. To collect new evidence directly into the existing saboteur repository, source env.sh and explicitly override EVIDENCE_DIR to the absolute field-runs/apps/lobsters path; record that command/path change with the new run. Do not overwrite the preserved original logs. commands.sh still records the historical absolute working paths.

Provisioning was performed without system installation rights. The Ruby binary package's text-script shebangs were changed, native headers were extracted locally, and the original libvips attempt was replaced after its recorded failure. This is not an unchanged app setup and is not a successful saboteur CI-flow test.

runmeasured.py uses time.time() subtraction for elapsed wall time. The recorded timestamps and raw timing value are preserved, but a monotonic clock was not used. Linux RUSAGE_CHILDREN.ru_maxrss is peak child-process RSS, not summed process-tree usage, database-service memory or whole-machine memory. stdout/stderr were captured separately by the execution environment, not by this helper.

Baseline exit status is preserved without subtraction or adjustment. Known pre-existing failures are named with their reasons in findings.md and the original RSpec JSON. No mutation run or whole-suite-map result is present yet. Rebuilding every historical PR's dependency environment is still unverified.


# Chatwoot: full environment and replay notes

Historical preparation-window records. Release-wait statements below describe that window, not the new main-pinned run.


# Chatwoot environment (apps/chatwoot)

## App
- repo: https://github.com/chatwoot/chatwoot
- pinned SHA: 7fe41fe03731fc2f5b1841b84351386962d2fd05 (was develop HEAD at fetch 2026-10-23 ~21:43 IST; verified in-history)
- Rails 7.2.3.1, RSpec; .ruby-version 3.4.4; .node-version 24.13.0; packageManager pnpm@10.2.0
- size at pin: 2957 tracked Ruby files, 1014 *_spec.rb (665 CE after stripping spec/enterprise per FOSS CI)

## Host (sandbox, not the user's machine)
- Ubuntu 22.04.5 LTS x86_64, 2 CPU, 1.9 GB RAM (1.7 GB available), 20 GB free disk, NO sudo
- nothing preinstalled for the app: no ruby, no postgres server headers, no redis-server, no pgvector

## Toolchain (all built/installed under $HOME, no system changes) - SETUP DEVIATION from docs (docs assume apt/sudo)
- ruby 3.4.4 from source (cache.ruby-lang.org tarball), openssl 3.0.16 + libyaml 0.2.5 from source
- postgresql 16.10 from source + pgvector 0.8.0 + contrib pg_stat_statements/pg_trgm/pgcrypto (pgcrypto linked to openssl 3.0.16)
- redis 7.2.5 from source
- node 24.13.0 official tarball, pnpm 10.2.0 via corepack
- bundler 2.5.16 (BUNDLED WITH), 356 gems installed via bundle install, pnpm i ok

## Services (running on localhost)
- postgres 16.10 port 5432, db chatwoot_test, schema loaded (110 tables), extensions: vector 0.8.0, pg_stat_statements, pg_trgm, pgcrypto, plpgsql
- redis 7.2.5 port 6379

## Deviations / friction recorded (details in findings.md)
1. Docs' apt/sudo install path impossible (no sudo): whole toolchain source-built.
2. First initdb defaulted to SQL_ASCII (no locale env) -> db:create failed; re-init with -E UTF8 --locale=C.UTF-8.
3. schema.rb requires pg_stat_statements + pgcrypto + pg_trgm; source postgres needed contrib modules built (pgcrypto needed openssl headers/rpath fix).
4. ruby openssl ext initially failed (openssl installed libs to lib64/, ruby extconf looked in lib/); fixed via symlinks + ext rebuild.

## saboteur
- version: NOT RUN yet. 0.13.0 not released; versioned saboteur measurements held until main sends verified 0.13.0 SHA.


# Chatwoot evidence replay notes

Raw successful-run helpers are in helpers/run-baseline.sh and helpers/run-baseline-extra.sh. They assume the historical working directory $HOME/fieldruns/chatwoot-git and evidence root $HOME/fieldruns/evidence/apps/chatwoot. helpers/env.sh configures the locally built toolchain. Before replay, create the historical evidence directories and copy helpers/env.sh to $HOME/fieldruns/env.sh, or explicitly change and record these paths for a new run. Do not overwrite preserved original evidence.

helpers/provision.sh and commands.sh are grouped provisioning recipes, not a literal complete attempt record. commands.sh.source preserves the supplied source text. The source-build recipe and published helper packaging have not been rerun from this evidence directory. Ensure $HOME/local/lib exists before the provisioner's symlink step. Generate local test keys from the public-safe template; no saved private application keys are included. Record any changes and new outputs rather than silently replacing originals.

The baseline scripts do not reliably propagate a failed RSpec exit as their own shell exit because they end with echo. Their recorded exit_code in meta.env and the RSpec JSON/log are the evidence for the actual command outcome; wrapper success alone is not enough. Do not use these wrappers' final shell status as a CI gate without a separately reviewed change.

Timing uses integer date timestamps and a polling loop, not a monotonic high-resolution process-only clock. Memory uses ps -o rss --ppid <rspec_pid> -p <rspec_pid>, so only the parent and direct children are sampled. The raw metadata's phrase 'process tree' is broader than the command supports. Peak RSS remains the original observed value; no correction or implied total is invented.

All path references beginning apps/chatwoot/ are relative to the field-runs/ evidence root. The source MANIFEST includes a self-checksum that does not match itself; every non-manifest file matched at receipt. MANIFEST-source.sha256 preserves that source file, not a claim that the self-row validates.


# Solidus: full environment and replay notes

Historical preparation-window records. Release-wait statements below describe that window, not the new main-pinned run.


# Solidus field-run environment

- App: solidusio/solidus, pinned SHA 07d5aff446586f6ab8ca024e2d8d08ee3e0463d8 (2026-10-20T14:12:09-07:00, merge of PR #6705)
- Repo shape: multi-gem engine (core, backend, api, admin, promotions, sample, storefront); suite under test: `cd core && bundle exec rspec` (README "Run an individual test suite"), SQLite 3 default
- OS: Ubuntu 22.04.5 LTS, kernel 6.1.158+ x86_64
- CPU: 2 cores; RAM: 1.9 GB total (~1.7 GB available); swap: 0
- System sqlite3 CLI: 3.37.2 (spec DBs use the sqlite3 rubygem)
- Ruby: 3.4.6 (2025-09-16 revision dbd83256b1) +PRISM [x86_64-linux], ruby-builder toolcache tarball (built for prefix /opt/hostedtoolcache/Ruby/3.4.6/x64) relocated to /home/sandbox/ruby34cache/3.4.6/x64.
  DEVIATION (unsupported configuration): the prefix string was patched IN-PLACE inside bin/ruby and libruby.so.3.4.6 with an equal-length replacement (35 bytes) plus matching edits to rbconfig.rb/pkgconfig/bin-shebangs. This is a hand-modified binary runtime, NOT an officially supported install; ruby-builder/rvm/ruby-install do not document this relocation as supported.
  Probes passed before baseline (exact list): ruby --version; $LOAD_PATH has all 8 expected entries; 43 stdlib/default-gem requires all OK; default versions outside bundler json 2.9.1 / psych 5.2.2 / openssl 3.3.0; bundle install completed (202 gems, psych 5.5.0 native ext compiled); under bundle exec, psych 5.5.0 loads from the lockfile-pinned gem path (no default-gem shadowing); smoke specs: spec/lib/spree/core/version_spec.rb (3 examples, 0 failures), spec/models/spree/address_spec.rb (36 examples, 0 failures, exercises DummyApp boot + sqlite auto-migrate).
  Remaining uncertainty: these probes do not establish full equivalence with an officially supported install. Untested stdlib/native-extension surface may behave differently; any test failure whose cause is ambiguous MUST be treated as environment-suspect and cross-checked (e.g. rerun in isolation) before being attributed to the app or to saboteur. The earlier broken relocation (load-path truncation + gem shadowing) was found only by probing, so absence of symptoms is not proof of correctness.
- RubyGems 3.6.9; Bundler 2.6.9; git 2.34.1
- libyaml: sandbox has no system libyaml headers; Ubuntu 22.04 libyaml-0-2/libyaml-dev debs extracted user-space to ~/sysroot (PKG_CONFIG_PATH + LD_LIBRARY_PATH set) so psych 5.5.0 native ext compiles. Documented deviation; no app or Gemfile change.
- Toolchain validation before baseline: 43 stdlib/default-gem requires all OK; versions json 2.9.1 / psych 5.2.2 / openssl 3.3.0 outside bundler (expected defaults); bundle exec psych check below.
- saboteur version: null (0.13.0 not released at prep time; SHA pending from main)
- Dummy app: boots in-process via core/spec/rails_helper.rb (DummyApp.setup + auto_migrate); no separate documented setup step for the core suite
- F-ENV-1 (documented-flow gap): the README core-suite path needs a system libvips that is never mentioned; without it, 8 image-variant specs fail (see findings.md). CI installs libvips out-of-band.


# Recorded PR selections

These are historical selected PRs and direct-spec controls, not completed mutation replays. New SQLite-era selection still needs current execution verification.


## lobsters

```json
{
  "app": "lobsters",
  "repo": "https://github.com/lobsters/lobsters",
  "pinned_sha": "407536444934ac7d78f4ce1c18f228e3891a8663",
  "selected_at": "2026-10-23T21:48:00+05:30",
  "selection_rule": "5 real merged PRs, each an ancestor of the pinned SHA, each touching app/ Ruby code WITH matching spec/ changes, small diffs (<=6 files), spread across models/controllers/routing/search. Verified via GitHub API (commit->PR association) and local git (ancestry, file lists).",
  "prs": [
    {
      "number": 2231,
      "url": "https://github.com/lobsters/lobsters/pull/2231",
      "title": "Comment#parents: order by depth so no-JS reply/edit pages render ancestors root-first",
      "merged_at": "2026-09-30T13:15:33Z",
      "base_sha": "372345a2cca5ed8e5d3376dcdc7e0a33e7f4f17c",
      "head_sha": "9fd8f5fca9b5f93a465a079cd0847b17b2acebe8",
      "app_files": [
        "app/models/comment.rb"
      ],
      "spec_files": [
        "spec/mailers/email_reply_mailer_spec.rb",
        "spec/models/comment_spec.rb",
        "spec/requests/comments_spec.rb"
      ]
    },
    {
      "number": 2204,
      "url": "https://github.com/lobsters/lobsters/pull/2204",
      "title": "fix story #is_gone? condition",
      "merged_at": "2026-09-04T20:37:45Z",
      "base_sha": "8f1b50061e5ef0b88ddbadc675395f7b5cf4eb76",
      "head_sha": "ed722e449227b39ab6268f4260aaa66df95275bd",
      "app_files": [
        "app/models/story.rb"
      ],
      "spec_files": [
        "spec/models/story_spec.rb"
      ]
    },
    {
      "number": 2156,
      "url": "https://github.com/lobsters/lobsters/pull/2156",
      "title": "fix username moderation log",
      "merged_at": "2026-09-14T01:31:17Z",
      "base_sha": "9a773eac0b49fd86b16585ad503de9a51919c496",
      "head_sha": "d9998c2555317db7b3cb9a159ef7878ff993ab78",
      "app_files": [
        "app/controllers/settings_controller.rb"
      ],
      "spec_files": [
        "spec/controllers/settings_controller_spec.rb"
      ]
    },
    {
      "number": 2090,
      "url": "https://github.com/lobsters/lobsters/pull/2090",
      "title": "Adding redirects for /top rss endpoints to .rss versions",
      "merged_at": "2026-07-16T15:03:06Z",
      "base_sha": "81ba649e1a667afddd1c780d0aeb37bad37ac308",
      "head_sha": "87e1e318fc7cc914646605c34dae39ff4d28ef34",
      "app_files": [
        "app/controllers/home_controller.rb",
        "config/routes.rb"
      ],
      "spec_files": [
        "spec/controllers/home_controller_spec.rb",
        "spec/routing/home_spec.rb"
      ]
    },
    {
      "number": 2143,
      "url": "https://github.com/lobsters/lobsters/pull/2143",
      "title": "Remove ref tracking query param from submitted URLs",
      "merged_at": "2026-07-15T12:40:32Z",
      "base_sha": "e72cf85f041cfa82157173e0af82bce693e5c9d0",
      "head_sha": "81ba649e1a667afddd1c780d0aeb37bad37ac308",
      "app_files": [
        "app/models/story.rb"
      ],
      "spec_files": [
        "spec/models/story_spec.rb"
      ],
      "substitution_reason": "replaces #2053: #2053's head tree (2026-07-09) is MySQL/trilogy era and its documented bin/setup requires a MySQL server at 127.0.0.1:3306, unavailable in this no-sudo sandbox (F-ENV-2). #2143 is the nearest confirmed SQLite-era merged PR, ancestor of pin, story.rb + story_spec.rb."
    }
  ],
  "spare": [
    {
      "number": 2102,
      "url": "https://github.com/lobsters/lobsters/pull/2102",
      "title": "RSS feed for user's comments",
      "merged_at": "2026-07-09T21:11:15Z",
      "base_sha": "6aec11c292fe9367720d069098c5e65754e1168b",
      "head_sha": "34e7ca10043bed8d47e2510e00111db54e6db2ab",
      "reason_kept_as_spare": "includes .rss.builder view template; usable if one of the 5 proves unrunnable"
    },
    {
      "number": 2053,
      "url": "https://github.com/lobsters/lobsters/pull/2053",
      "title": "Fix title shortword search handling",
      "base_sha": "04c0dc8a76983038e3f6e604f0c4cb195a78493e",
      "head_sha": "3f81b9f3696e5d64153ab9254f6f9e45a39a72eb",
      "reason_demoted": "head tree requires MySQL (trilogy) at 127.0.0.1:3306; bin/setup db:create fails without a server (F-ENV-2); usable only if MySQL is provisioned"
    }
  ]
}
```


## chatwoot

```json
[
  {
    "pr": 16185,
    "url": "https://github.com/chatwoot/chatwoot/pull/16185",
    "head_sha": "4fb7c05f95e04e70b65141ff19bbdb9328095da8",
    "base_sha": "dac03318c737bf76846298534ca3368e8afd9b97",
    "title": "fix: fall back to SQL search on OpenSearch errors (#16185)",
    "stat": "2 files changed, 72 insertions(+), 22 deletions(-)",
    "ruby_files": [
      "app/services/search_service.rb"
    ],
    "spec_files": [
      "spec/services/search_service_spec.rb"
    ],
    "test_selection": [
      "spec/services/search_service_spec.rb"
    ],
    "baseline_coverage": "in models+services baseline",
    "notes": "PR's own spec is the direct spec for the changed file",
    "tree_checks": {
      "base": "40 examples 0 failures",
      "head": "37 examples 0 failures"
    },
    "tree_check_note": "worktree at base/head SHA, CE strip applied, tree's own db:schema:load, test_selection specs; logs in logs/pr-checks/"
  },
  {
    "pr": 15978,
    "url": "https://github.com/chatwoot/chatwoot/pull/15978",
    "head_sha": "fbb90f753cb04cd6ad96c48bf5202fa18a0b58af",
    "base_sha": "96b13cc2060d4aaf63ba61a2a1d92665e0d743f1",
    "title": "fix: skip IMAP emails that another fetch job already saved (#15978)",
    "stat": "3 files changed, 46 insertions(+)",
    "ruby_files": [
      "app/mailboxes/imap/imap_mailbox.rb"
    ],
    "spec_files": [
      "spec/mailboxes/imap/imap_mailbox_spec.rb"
    ],
    "test_selection": [
      "spec/mailboxes/imap/imap_mailbox_spec.rb"
    ],
    "baseline_coverage": "OUTSIDE models+services baseline - additional baseline run required before this PR's mutation run",
    "notes": "direct spec exists and is the PR's own spec",
    "tree_checks": {
      "base": "21 examples 0 failures",
      "head": "23 examples 0 failures"
    },
    "tree_check_note": "worktree at base/head SHA, CE strip applied, tree's own db:schema:load, test_selection specs; logs in logs/pr-checks/"
  },
  {
    "pr": 15807,
    "url": "https://github.com/chatwoot/chatwoot/pull/15807",
    "head_sha": "00960a09d1a19a4d954cd20c5ad5b8b8d01a6472",
    "base_sha": "081bd68ab22a167e2af19e46f89c97e994a9f1c4",
    "title": "fix: preserve automation labels on unrelated conversation saves (#15807)",
    "stat": "4 files changed, 249 insertions(+), 5 deletions(-)",
    "ruby_files": [
      "app/jobs/migration/conversation_batch_cache_label_job.rb",
      "app/models/concerns/labelable.rb",
      "app/models/concerns/labelable/persistence.rb"
    ],
    "spec_files": [
      "spec/models/concerns/labelable/persistence_spec.rb"
    ],
    "test_selection": [
      "spec/models/concerns/labelable/persistence_spec.rb"
    ],
    "baseline_coverage": "in models+services baseline",
    "notes": "no spec/models/concerns/labelable_spec.rb exists; persistence_spec is the direct spec",
    "tree_checks": {
      "base": "NOT APPLICABLE - persistence.rb and persistence_spec.rb are both introduced by this PR (verified via git show); no direct spec exists at base",
      "head": "23 examples 0 failures"
    },
    "tree_check_note": "worktree at base/head SHA, CE strip applied, tree's own db:schema:load, test_selection specs; logs in logs/pr-checks/"
  },
  {
    "pr": 16182,
    "url": "https://github.com/chatwoot/chatwoot/pull/16182",
    "head_sha": "5c2b3f78bd3f845d2bc95c745a7698c4a5946599",
    "base_sha": "7a86dea8d0befa545c0ba2501b9f8c1f7e3089bd",
    "title": "feat: configurable auto-resolve minimum and schedule (#16182)",
    "stat": "13 files changed, 59 insertions(+), 11 deletions(-)",
    "ruby_files": [
      "app/jobs/trigger_scheduled_items_job.rb",
      "app/models/account.rb",
      "app/models/concerns/account_settings_schema.rb",
      "lib/limits.rb"
    ],
    "spec_files": [
      "spec/configs/schedule_spec.rb",
      "spec/jobs/trigger_scheduled_items_job_spec.rb",
      "spec/models/account_spec.rb"
    ],
    "test_selection": [
      "spec/jobs/trigger_scheduled_items_job_spec.rb",
      "spec/models/account_spec.rb"
    ],
    "baseline_coverage": "jobs spec OUTSIDE baseline - additional baseline run required; account_spec in baseline",
    "notes": "lib/limits.rb has no direct spec in repo (grep Limits:: -> only unrelated references); account_settings_schema has no direct spec",
    "tree_checks": {
      "base": "81 examples 0 failures (trigger_scheduled_items_job_spec + account_spec)",
      "head": "82 examples 0 failures"
    },
    "tree_check_note": "worktree at base/head SHA, CE strip applied, tree's own db:schema:load, test_selection specs; logs in logs/pr-checks/"
  },
  {
    "pr": 16253,
    "url": "https://github.com/chatwoot/chatwoot/pull/16253",
    "head_sha": "00b13f7873ed92bbc01fc8b0292dd8f7d4a5c1d6",
    "base_sha": "012bb8edb8f7de1454cd11ced1e1136b3656d694",
    "title": "fix(stripe): disconnect accounts when the app is uninstalled (#16253)",
    "stat": "8 files changed, 184 insertions(+), 10 deletions(-)",
    "ruby_files": [
      "app/controllers/super_admin/app_configs_controller.rb",
      "app/controllers/webhooks/stripe_app_controller.rb",
      "app/services/integrations/stripe/uninstallation_service.rb"
    ],
    "spec_files": [
      "spec/services/integrations/stripe/uninstallation_service_spec.rb"
    ],
    "test_selection": [
      "spec/services/integrations/stripe/uninstallation_service_spec.rb"
    ],
    "baseline_coverage": "in models+services baseline",
    "notes": "no spec exists for webhooks/stripe_app_controller or super_admin/app_configs_controller (grep verified); uninstallation_service_spec is the only direct spec",
    "tree_checks": {
      "base": "NOT APPLICABLE - uninstallation_service.rb and its spec are both introduced by this PR (verified via git show); no direct spec exists at base",
      "head": "3 examples 0 failures"
    },
    "tree_check_note": "worktree at base/head SHA, CE strip applied, tree's own db:schema:load, test_selection specs; logs in logs/pr-checks/"
  }
]
```


## solidus

```csv
# Solidus PR replay selection (generated 2026-10-23T16:13:19Z)
# Rule: scan first-parent merges newest-first from pin 07d5aff446586f6ab8ca024e2d8d08ee3e0463d8;
# keep merges touching core/app or core/lib (>=1 line) with total diff <=300 lines; skip merges without a public PR number;
# take first 5, requiring >=2 with core/spec changes (result: all 5 have spec changes).
pr,base_sha,head_sha,src_lines,spec_lines,total_lines,url
6691,7c1842d9099d76713b4d2a69001eac914a5f16d3,1514f27fc7b257ab1ae5bab5a3646a04f256b06a,10,36,46,https://github.com/solidusio/solidus/pull/6691
6677,198c66c2f36fae2aab622851e2945cb66ce9b44b,4dd53128473a4e0c7b7fdbb6d152e35a5ca7bb1b,3,4,10,https://github.com/solidusio/solidus/pull/6677
6697,5b47ff22b600011f369e8da0de60bfe60bb27039,8950d6cc6b4d79c65b8a58172e60453d4d5e1d95,15,60,75,https://github.com/solidusio/solidus/pull/6697
6701,5158ea6d0ebf63d29acce4ae9bc8332d59e2c321,5b47ff22b600011f369e8da0de60bfe60bb27039,12,29,51,https://github.com/solidusio/solidus/pull/6701
6692,78fb02ba19a443a6648aa870634700eb2c1a0a94,c27efd40c184eba0c758ecc9429cf23551000f5f,24,50,74,https://github.com/solidusio/solidus/pull/6692

```

# Original full-baseline failures

Unadjusted failures below are taken from original RSpec JSON. They are not saboteur mutation kills or authorized exclusions. Repeated observations do not prove non-flakiness.


## lobsters


### ./spec/extras/github_spec.rb[1:2:1]

Github CGI.parse should work

```text
{
  "class": "NoMethodError",
  "message": "undefined method 'parse' for class CGI",
  "backtrace": [
    "./spec/extras/github_spec.rb:15:in 'block (3 levels) in <top (required)>'"
  ]
}
```


### ./spec/features/user_administration_spec.rb[1:3]

User Administration banning

```text
{
  "class": "RSpec::Expectations::ExpectationNotMetError",
  "message": "Expected 0 to eq 1.",
  "backtrace": [
    "./spec/features/user_administration_spec.rb:50:in 'block (2 levels) in <top (required)>'"
  ]
}
```


## chatwoot


No failed examples in the original primary baseline. Pending examples and scope limits remain in the original report.


## solidus


### ./spec/models/spree/image_spec.rb[1:5:5]

Spree::Image attachment details computes attachment height

```text
{
  "class": "RSpec::Expectations::ExpectationNotMetError",
  "message": "\nexpected: 1\n     got: nil\n\n(compared using ==)\n",
  "backtrace": [
    "./spec/models/spree/image_spec.rb:71:in 'block (3 levels) in <top (required)>'"
  ]
}
```


### ./spec/models/spree/image_spec.rb[1:5:3]

Spree::Image attachment details returns attachment url

```text
{
  "class": "NoMethodError",
  "message": "undefined method 'new' for nil",
  "backtrace": [
    "./app/models/concerns/spree/active_storage_adapter/attachment.rb:38:in 'Spree::ActiveStorageAdapter::Attachment#variant'",
    "./app/models/concerns/spree/active_storage_adapter/attachment.rb:28:in 'Spree::ActiveStorageAdapter::Attachment#url'",
    "./app/models/concerns/spree/active_storage_adapter.rb:92:in 'Spree::ActiveStorageAdapter#url'",
    "./spec/models/spree/image_spec.rb:63:in 'block (3 levels) in <top (required)>'"
  ]
}
```


### ./spec/models/spree/image_spec.rb[1:5:4]

Spree::Image attachment details computes attachment width

```text
{
  "class": "RSpec::Expectations::ExpectationNotMetError",
  "message": "\nexpected: 1\n     got: nil\n\n(compared using ==)\n",
  "backtrace": [
    "./spec/models/spree/image_spec.rb:67:in 'block (3 levels) in <top (required)>'"
  ]
}
```


### ./spec/models/spree/concerns/active_storage_adapter/attachment_spec.rb[1:1:4]

Spree::ActiveStorageAdapter::Attachment#variant strips definitions

```text
{
  "class": "NoMethodError",
  "message": "undefined method 'new' for nil",
  "backtrace": [
    "./app/models/concerns/spree/active_storage_adapter/attachment.rb:38:in 'Spree::ActiveStorageAdapter::Attachment#variant'",
    "./spec/models/spree/concerns/active_storage_adapter/attachment_spec.rb:44:in 'block (3 levels) in <top (required)>'"
  ]
}
```


### ./spec/models/spree/concerns/active_storage_adapter/attachment_spec.rb[1:1:2]

Spree::ActiveStorageAdapter::Attachment#variant converts to resize_to_limit when definition ends with >

```text
{
  "class": "NoMethodError",
  "message": "undefined method 'new' for nil",
  "backtrace": [
    "./app/models/concerns/spree/active_storage_adapter/attachment.rb:38:in 'Spree::ActiveStorageAdapter::Attachment#variant'",
    "./spec/models/spree/concerns/active_storage_adapter/attachment_spec.rb:24:in 'block (3 levels) in <top (required)>'"
  ]
}
```


### ./spec/models/spree/concerns/active_storage_adapter/attachment_spec.rb[1:1:5]

Spree::ActiveStorageAdapter::Attachment#variant defaults to the image's width and height

```text
{
  "class": "NoMethodError",
  "message": "undefined method 'new' for nil",
  "backtrace": [
    "./app/models/concerns/spree/active_storage_adapter/attachment.rb:38:in 'Spree::ActiveStorageAdapter::Attachment#variant'",
    "./spec/models/spree/concerns/active_storage_adapter/attachment_spec.rb:54:in 'block (3 levels) in <top (required)>'"
  ]
}
```


### ./spec/models/spree/concerns/active_storage_adapter/attachment_spec.rb[1:1:1]

Spree::ActiveStorageAdapter::Attachment#variant converts to resize_to_limit when definition doesn't contain any special symbol

```text
{
  "class": "NoMethodError",
  "message": "undefined method 'new' for nil",
  "backtrace": [
    "./app/models/concerns/spree/active_storage_adapter/attachment.rb:38:in 'Spree::ActiveStorageAdapter::Attachment#variant'",
    "./spec/models/spree/concerns/active_storage_adapter/attachment_spec.rb:14:in 'block (3 levels) in <top (required)>'"
  ]
}
```


### ./spec/models/spree/concerns/active_storage_adapter/attachment_spec.rb[1:1:3]

Spree::ActiveStorageAdapter::Attachment#variant converts to resize_to_fill when definition ends with ^

```text
{
  "class": "NoMethodError",
  "message": "undefined method 'new' for nil",
  "backtrace": [
    "./app/models/concerns/spree/active_storage_adapter/attachment.rb:38:in 'Spree::ActiveStorageAdapter::Attachment#variant'",
    "./spec/models/spree/concerns/active_storage_adapter/attachment_spec.rb:34:in 'block (3 levels) in <top (required)>'"
  ]
}
```


# Evidence packaging and interpretation

# Evidence composition notes

Raw application logs, RSpec JSON and source measurement records are retained. No baseline or mutation exit code was adjusted. No app baseline was rerun during report composition.

Source stage envelopes were normalized to the flat stages mapping expected by the report generator. Original source stage files remain alongside them. Later stage labels distinguish unstarted versioned work from completed preparation measurements.

Solidus per-tree measurement records gained evidence_paths pointing to their existing RSpec JSON/logs; originals remain measurement-source.json. Their numeric fields were not changed. Baseline-red IDs were extracted from original RSpec JSON into baseline-red-candidates.json and are not actual mutation exclusions.

Published replay instructions distinguish grouped provisioning recipes from literal command history. Original supplied command descriptions are retained as source files where the composed wording changed. The helpers were not rerun from the final evidence directory. Unsupported runtime relocation and setup deviations remain visible.

Memory measurements are method-dependent: Lobsters uses peak child RSS from RUSAGE_CHILDREN; Chatwoot and Solidus sample the RSpec process and direct children, not all descendants or database services. Neither approach gives whole-machine memory cost. Sampled maxima can miss peaks. Timing methods and RSpec example duration are separate and must not be interchanged.

The report generator was independently checked with synthetic fixtures and actual baseline inputs. This verifies evidence-tool behavior, not saboteur compatibility, complete PR coverage, app setup equivalence or mutation verdict correctness. No triage outcome exists without raw versioned mutation reports.


## Raw evidence index

Paths below identify retained evidence files. The PDF includes human-readable results and failures, not binary artifacts or a dump of every raw JSON example.

```text
apps/chatwoot/ENV.md
apps/chatwoot/MANIFEST-source-2221.sha256
apps/chatwoot/MANIFEST-source.sha256
apps/chatwoot/REPRODUCE.md
apps/chatwoot/commands.sh
apps/chatwoot/commands.sh.source
apps/chatwoot/findings.md
apps/chatwoot/helpers/chatwoot.env.template
apps/chatwoot/helpers/env.sh
apps/chatwoot/helpers/provision.sh
apps/chatwoot/helpers/run-baseline-extra.sh
apps/chatwoot/helpers/run-baseline.sh
apps/chatwoot/logs/baseline-extra-rspec.json
apps/chatwoot/logs/baseline-extra-rspec.log
apps/chatwoot/logs/baseline-rspec.json
apps/chatwoot/logs/baseline-rspec.log
apps/chatwoot/logs/baseline-rspec.time
apps/chatwoot/logs/pr-checks/15807-base-meta.env
apps/chatwoot/logs/pr-checks/15807-base-rspec.log
apps/chatwoot/logs/pr-checks/15807-base-schema.log
apps/chatwoot/logs/pr-checks/15807-head-meta.env
apps/chatwoot/logs/pr-checks/15807-head-rspec.log
apps/chatwoot/logs/pr-checks/15807-head-schema.log
apps/chatwoot/logs/pr-checks/15978-base-meta.env
apps/chatwoot/logs/pr-checks/15978-base-rspec.log
apps/chatwoot/logs/pr-checks/15978-base-schema.log
apps/chatwoot/logs/pr-checks/15978-head-meta.env
apps/chatwoot/logs/pr-checks/15978-head-rspec.log
apps/chatwoot/logs/pr-checks/15978-head-schema.log
apps/chatwoot/logs/pr-checks/16182-base-meta.env
apps/chatwoot/logs/pr-checks/16182-base-rspec.log
apps/chatwoot/logs/pr-checks/16182-base-schema.log
apps/chatwoot/logs/pr-checks/16182-head-meta.env
apps/chatwoot/logs/pr-checks/16182-head-rspec.log
apps/chatwoot/logs/pr-checks/16182-head-schema.log
apps/chatwoot/logs/pr-checks/16185-base-meta.env
apps/chatwoot/logs/pr-checks/16185-base-rspec.log
apps/chatwoot/logs/pr-checks/16185-base-schema.log
apps/chatwoot/logs/pr-checks/16185-head-meta.env
apps/chatwoot/logs/pr-checks/16185-head-rspec.log
apps/chatwoot/logs/pr-checks/16185-head-schema.log
apps/chatwoot/logs/pr-checks/16253-base-meta.env
apps/chatwoot/logs/pr-checks/16253-base-rspec.log
apps/chatwoot/logs/pr-checks/16253-base-schema.log
apps/chatwoot/logs/pr-checks/16253-head-meta.env
apps/chatwoot/logs/pr-checks/16253-head-rspec.log
apps/chatwoot/logs/pr-checks/16253-head-schema.log
apps/chatwoot/metadata.json
apps/chatwoot/reports/baseline/measurement.json
apps/chatwoot/reports/baseline/meta.env
apps/chatwoot/reports/baseline/pending_examples.json
apps/chatwoot/reports/baseline-extra/measurement.json
apps/chatwoot/reports/baseline-extra/meta.env
apps/chatwoot/selected_prs.json
apps/chatwoot/stages.json
apps/chatwoot/stages.json.source
apps/lobsters/ENV.md
apps/lobsters/REPRODUCE.md
apps/lobsters/commands-latest-source.sh
apps/lobsters/commands.sh
apps/lobsters/env.sh
apps/lobsters/findings.md
apps/lobsters/logs/baseline-failures-recheck.log
apps/lobsters/logs/baseline-rspec.json
apps/lobsters/logs/baseline-rspec.log
apps/lobsters/logs/bin-setup.log
apps/lobsters/logs/pr-bases-driver.log
apps/lobsters/logs/pr-trees-driver.log
apps/lobsters/logs/pr2053-head-specs.log
apps/lobsters/logs/pr2090-base-specs.json
apps/lobsters/logs/pr2090-base-specs.log
apps/lobsters/logs/pr2090-head-specs.json
apps/lobsters/logs/pr2090-head-specs.log
apps/lobsters/logs/pr2143-base-specs.json
apps/lobsters/logs/pr2143-base-specs.log
apps/lobsters/logs/pr2143-head-specs.json
apps/lobsters/logs/pr2143-head-specs.log
apps/lobsters/logs/pr2156-base-specs.json
apps/lobsters/logs/pr2156-base-specs.log
apps/lobsters/logs/pr2156-head-specs.json
apps/lobsters/logs/pr2156-head-specs.log
apps/lobsters/logs/pr2204-base-specs.json
apps/lobsters/logs/pr2204-base-specs.log
apps/lobsters/logs/pr2204-head-specs.json
apps/lobsters/logs/pr2204-head-specs.log
apps/lobsters/logs/pr2231-base-specs.json
apps/lobsters/logs/pr2231-base-specs.log
apps/lobsters/logs/pr2231-head-specs.json
apps/lobsters/logs/pr2231-head-specs.log
apps/lobsters/logs/ruby400-install.log
apps/lobsters/metadata.json
apps/lobsters/prs/selected_prs.json
apps/lobsters/reports/baseline/measurement.json
apps/lobsters/reports/pr2090-base-specs/measurement-raw.json
apps/lobsters/reports/pr2090-base-specs/measurement.json
apps/lobsters/reports/pr2090-head-specs/measurement-raw.json
apps/lobsters/reports/pr2090-head-specs/measurement.json
apps/lobsters/reports/pr2143-base-specs/measurement-raw.json
apps/lobsters/reports/pr2143-base-specs/measurement.json
apps/lobsters/reports/pr2143-head-specs/measurement-raw.json
apps/lobsters/reports/pr2143-head-specs/measurement.json
apps/lobsters/reports/pr2156-base-specs/measurement-raw.json
apps/lobsters/reports/pr2156-base-specs/measurement.json
apps/lobsters/reports/pr2156-head-specs/measurement-raw.json
apps/lobsters/reports/pr2156-head-specs/measurement.json
apps/lobsters/reports/pr2204-base-specs/measurement-raw.json
apps/lobsters/reports/pr2204-base-specs/measurement.json
apps/lobsters/reports/pr2204-head-specs/measurement-raw.json
apps/lobsters/reports/pr2204-head-specs/measurement.json
apps/lobsters/reports/pr2231-base-specs/measurement-raw.json
apps/lobsters/reports/pr2231-base-specs/measurement.json
apps/lobsters/reports/pr2231-head-specs/measurement-raw.json
apps/lobsters/reports/pr2231-head-specs/measurement.json
apps/lobsters/runmeasured.py
apps/lobsters/stages-0115-corrected-source.json
apps/lobsters/stages-source.json
apps/lobsters/stages.json
apps/solidus/ENV.md
apps/solidus/baseline-red-candidates.json
apps/solidus/commands.sh
apps/solidus/commands.sh.v2-source
apps/solidus/findings-source.md
apps/solidus/findings.md
apps/solidus/findings.md.v2-source
apps/solidus/helpers/env.sh
apps/solidus/helpers/helpers-original-snapshot-20261023T1653Z/env.sh
apps/solidus/helpers/helpers-original-snapshot-20261023T1653Z/measure.sh
apps/solidus/helpers/helpers-original-snapshot-20261023T1653Z/pr-tree-checks.sh
apps/solidus/helpers/measure.sh
apps/solidus/helpers/pr-tree-checks.sh
apps/solidus/logs/baseline-failures-recheck.log
apps/solidus/logs/baseline-rspec.json
apps/solidus/logs/baseline-runner.log
apps/solidus/logs/env-bundle-install.log
apps/solidus/logs/env-smoke.log
apps/solidus/logs/pr-tree-checks.log
apps/solidus/logs/pr6677-base-scope-rspec.json
apps/solidus/logs/pr6677-head-scope-rspec.json
apps/solidus/logs/pr6691-base-scope-rspec.json
apps/solidus/logs/pr6691-head-scope-rspec.json
apps/solidus/logs/pr6692-base-scope-rspec.json
apps/solidus/logs/pr6692-head-scope-rspec.json
apps/solidus/logs/pr6697-base-scope-rspec.json
apps/solidus/logs/pr6697-head-scope-rspec.json
apps/solidus/logs/pr6701-base-scope-rspec.json
apps/solidus/logs/pr6701-head-scope-rspec.json
apps/solidus/metadata.json
apps/solidus/pr-selection.csv
apps/solidus/relocate-ruby.sh
apps/solidus/replay-recipe.md
apps/solidus/replay-scope.md
apps/solidus/reports/baseline/measurement.json
apps/solidus/reports/baseline/stdout+stderr.log
apps/solidus/reports/pr6677-base-scope/measurement-source.json
apps/solidus/reports/pr6677-base-scope/measurement.json
apps/solidus/reports/pr6677-base-scope/stdout+stderr.log
apps/solidus/reports/pr6677-head-scope/measurement-source.json
apps/solidus/reports/pr6677-head-scope/measurement.json
apps/solidus/reports/pr6677-head-scope/stdout+stderr.log
apps/solidus/reports/pr6691-base-scope/measurement-source.json
apps/solidus/reports/pr6691-base-scope/measurement.json
apps/solidus/reports/pr6691-base-scope/stdout+stderr.log
apps/solidus/reports/pr6691-head-scope/measurement-source.json
apps/solidus/reports/pr6691-head-scope/measurement.json
apps/solidus/reports/pr6691-head-scope/stdout+stderr.log
apps/solidus/reports/pr6692-base-scope/measurement-source.json
apps/solidus/reports/pr6692-base-scope/measurement.json
apps/solidus/reports/pr6692-base-scope/stdout+stderr.log
apps/solidus/reports/pr6692-head-scope/measurement-source.json
apps/solidus/reports/pr6692-head-scope/measurement.json
apps/solidus/reports/pr6692-head-scope/stdout+stderr.log
apps/solidus/reports/pr6697-base-scope/measurement-source.json
apps/solidus/reports/pr6697-base-scope/measurement.json
apps/solidus/reports/pr6697-base-scope/stdout+stderr.log
apps/solidus/reports/pr6697-head-scope/measurement-source.json
apps/solidus/reports/pr6697-head-scope/measurement.json
apps/solidus/reports/pr6697-head-scope/stdout+stderr.log
apps/solidus/reports/pr6701-base-scope/measurement-source.json
apps/solidus/reports/pr6701-base-scope/measurement.json
apps/solidus/reports/pr6701-base-scope/stdout+stderr.log
apps/solidus/reports/pr6701-head-scope/measurement-source.json
apps/solidus/reports/pr6701-head-scope/measurement.json
apps/solidus/reports/pr6701-head-scope/stdout+stderr.log
apps/solidus/selection.csv
apps/solidus/stages-source.json
apps/solidus/stages.json
apps/solidus/stages.json.v2-source
```

# Lobsters CGI.parse failure: upstream investigation (2026-10-24)

**Verdict: the upstream CGI.parse failure class was fixed in January 2026 (issue #1845, PR #1846). Our observed failure is a sandbox environment artifact, not an app bug and not a cgi-gem regression. No new upstream issue is warranted on current evidence. A conditional standby draft is included at the bottom.**

All upstream reads were public and unauthenticated (GitHub REST API, raw.githubusercontent.com, rubygems.org). Nothing was posted upstream.

## 1. What we observed (raw evidence)

- Baseline at pinned SHA 407536444934ac7d78f4ce1c18f228e3891a8663 ("bump for Ruby joining this week's CVE-a-thon", 2026-10-23T15:06:27Z, = origin/main at qualification), Ruby 4.0.9 (ruby-builder prebuilt, revision 3e93b23afc), `bundle exec rspec` full suite: 913 examples, 2 failures, wall 35.345s, exit 1 (logs/baseline-rspec.json).
- CGI failure: `rspec ./spec/extras/github_spec.rb:14` "Github CGI.parse should work", NoMethodError "undefined method 'parse' for class CGI", backtrace pointing at **spec line 15** (`expect(CGI.parse("a"))`).
- Provenance note: the failing line is the sentinel spec (spec/extras/github_spec.rb:15), NOT the app callsite. The app callsite is extras/github.rb:21 (`ps = CGI.parse(res)` inside `Github.token_and_user_from_code`, GitHub account linking). That callsite was never executed by the failing example.
- Reproduced in: full baseline + 2 isolated rechecks (2026-10-23 21:55-21:56 IST) + fresh post-rebuild rerun of the 2 red files, 7 examples, 2 failures, exit 1, wall 7.56s (2026-10-24 06:38 IST). Repeated observations, not a formal non-flakiness proof; the cause is now explained structurally, so flakiness is moot for this failure.
- The second baseline failure (spec/features/user_administration_spec.rb:39 "banning", Expected 0 to eq 1) is a separate matter, see section 6 note.

## 2. Upstream history: this failure class is known and fixed

- Issue #1845 "Can't link GitHub accounts because CGI.parse is gone" (opened by pushcx 2026-01-04, closed as completed 2026-01-07): https://github.com/lobsters/lobsters/issues/1845
- Fix PR #1846 "`CGI.parse("oops")`" (caius, merged 2026-01-07, merge commit 708c4e1224cfda31b666aedca14d305f3287ce01): https://github.com/lobsters/lobsters/pull/1846
  - Fix approach: add `gem "cgi"` to the Gemfile (the rubygems cgi gem still provides the full library) plus a sentinel spec proving CGI.parse loads. That sentinel is the exact spec failing in our sandbox.
- Verified at pinned SHA and at current master (identical): Gemfile line 35 `gem "cgi"`; Gemfile.lock pins cgi 0.5.1 (sha256 e93fcafc69b8a934fe1e6146121fa35430efa8b4a4047c4893764067036f18e9), byte-identical to the lockfile at the January fix merge.

## 3. Claim check: "CGI.parse was removed in cgi 0.5.1" is FALSE

The field-run report attributed the failure to cgi gem 0.5.1 removing CGI.parse. Verified against the actual artifacts:

- Downloaded cgi 0.4.2, 0.5.0, 0.5.1, 0.5.2 from rubygems.org. ALL FOUR define `CGI.parse` (lib/cgi/core.rb) and their lib/cgi.rb requires cgi/core. The 0.5.1 gem shipped and installed by the field run does provide CGI.parse.
- Rubygems release dates: 0.5.0 (2025-06-04), 0.5.1 (2025-12-10), 0.5.2 (2026-06-23). https://rubygems.org/gems/cgi/versions
- The actual removal is in Ruby 4.0's stdlib, not the gem. Ruby 4.0.9's built-in lib/ruby/4.0.0/cgi.rb is a short shim: it requires only cgi/escape and warns "CGI library is removed from Ruby 4.0. Please use cgi/escape instead... If you need to use the full features of CGI library, Please install cgi gem." Verified byte-for-byte on the exact ruby-builder Ruby 4.0.9 used by the field run; the same shim exists in the ruby-builder Ruby 4.0.0 build. (Ruby 4.0.0 release notes' stdlib-compatibility section, referenced by #1845: https://www.ruby-lang.org/en/news/2025/12/25/ruby-4-0-0-released/)

## 4. Why our run failed anyway: RUBYLIB shadowing (proven on the identical Ruby build)

- The ruby-builder prebuilt tarball's compiled-in prefix (/opt/hostedtoolcache/Ruby/4.0.9/x64) does not exist in the sandbox, so the field-run environment sets RUBYLIB to the extracted tree's stdlib dirs (recorded in env.sh / ENV.md).
- RUBYLIB directories precede activated gem paths in $LOAD_PATH. Measured on the same build with the cgi 0.5.1 gem activated: $LOAD_PATH front = stdlib dirs, THEN the gem's lib.
- So `require "cgi"` resolved to Ruby's stdlib removal-shim, which defines only the escape functions; CGI.parse stayed undefined and the sentinel spec failed.
- Proof on the identical ruby-builder Ruby 4.0.9, cgi 0.5.1 gem installed from rubygems:
  - Shim-first RUBYLIB: `CGI.respond_to?(:parse)` = false (reproduces the baseline failure).
  - Gem lib first (`-I`, exactly what bundler/setup achieves on a standard install): parse = true, `CGI::VERSION` = "0.5.1".
  - Shim renamed away, shim-first RUBYLIB kept: parse = true, VERSION = "0.5.1".
- Conclusion: baseline failure F-BASE-1 is an artifact of the sandbox Ruby layout. On a correctly installed Ruby 4.0.9, lobsters' January fix still works. The app code at extras/github.rb:21 is fine.
- Suggested sandbox fix for the field worker: in the writable extracted ruby tree, rename lib/ruby/4.0.0/cgi.rb and lib/ruby/4.0.0/cgi/ aside (verified working above), or install Ruby 4.0.9 at a proper prefix. Then re-run the baseline. Caveat: renaming the shim means `require "cgi"` without the gem raises LoadError instead of warning; acceptable inside this sandbox since the app Gemfile always provides the gem.

## 5. Upstream CI status (checked October 24, 2026, before this snapshot)

- 2026-10-12, run 38323119585 (commit ab6fe2424, Ruby 4.0.0 era, same cgi 0.5.1 lockfile): test job SUCCESS; lint and security success; database-consistency failure. The mid-October main redness was the database-consistency job, not the test suite. https://github.com/lobsters/lobsters/actions/runs/38323119585
- 2026-10-23T15:06Z, run 39975413405 at the pinned commit 40753644 (the .ruby-version 4.0.0 -> 4.0.9 bump): test, lint, database-consistency FAILURE; security success. The "Check Dockerfile Ruby version" workflow also failed at that run. Previous main run 39975056886 (f6cba972a) failed all four jobs. https://github.com/lobsters/lobsters/actions/runs/39975413405
- Job logs are not publicly readable (API returns 403 "Must have admin rights"; the HTML page does not render logs without JS), so the CAUSE of the red test job at the pinned commit is UNCONFIRMED. Plausible candidates: ruby/setup-ruby not yet serving the hours-old Ruby 4.0.9, or a genuine 4.0.9 regression. Do not quote either as fact.
- No open upstream issue covers a CGI regression or the current CI red: all 11 cgi-tagged issues/PRs were reviewed (latest relevant are #1845/#1846 from January), and ~30 recent issues (Sept-Oct 2026) contain nothing about CGI or the failing suite.

## 6. Recommendation

1. Do NOT file a new upstream issue now. The CGI.parse removal is known and fixed upstream; our instance is a local environment artifact. Filing would be a duplicate/noise report to a maintainer who already handled it.
2. Fix the sandbox Ruby layout (section 4) and re-run the two red specs. Expected: github_spec goes green. If it STILL fails on a correctly installed Ruby 4.0.9, that is a genuine 4.0.9 regression of the #1846 fix - then file the standby draft in section 7, ideally after the upstream CI red cause is known.
3. Note on F-BASE-2 (banning spec, no email sent): separate, deterministic-looking failure, NOT CGI-related. Leads worth checking before calling it app-real: pinned tree is mid-repair of its email subsystem (parent commit e646f63a "restore transactional + notifications email; not yet mailing list mode", 2026-10-21) and upstream has open issues #2263 "Reply notifications are not being sent any more" (2026-10-21) and #2264 invitation email errors (2026-10-21). Possible relation, unverified. https://github.com/lobsters/lobsters/issues/2263

## 7. Standby issue draft - file ONLY if the sentinel still fails on a correctly installed Ruby 4.0.9

Title: CGI.parse sentinel spec fails on Ruby 4.0.9 (spec/extras/github_spec.rb)

Body:

```
Following up on #1845 / #1846.

On Ruby 4.0.9 (.ruby-version at current main, 40753644), the sentinel spec
added in #1846 fails:

    bundle exec rspec spec/extras/github_spec.rb

    Github CGI.parse should work
    Failure/Error: expect(CGI.parse("a"))
    NoMethodError: undefined method 'parse' for class CGI
    # ./spec/extras/github_spec.rb:15

The Gemfile still has `gem "cgi"` and Gemfile.lock pins cgi 0.5.1, which
does provide CGI.parse, so this looks like Ruby 4.0.9's stdlib cgi shim
shadowing the gem rather than the removal #1846 fixed.

extras/github.rb:21 uses CGI.parse in Github.token_and_user_from_code, so
GitHub account linking would raise at runtime if this reproduces outside
the test suite.

Environment: ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM
[x86_64-linux], bundler 4.0.3, cgi 0.5.1 from rubygems.
```

(If filed, add whether CI run https://github.com/lobsters/lobsters/actions/runs/39975413405 fails for the same reason once its logs are readable.)

## Source URLs

- https://github.com/lobsters/lobsters/issues/1845
- https://github.com/lobsters/lobsters/pull/1846
- https://github.com/lobsters/lobsters/commit/407536444934ac7d78f4ce1c18f228e3891a8663
- https://github.com/lobsters/lobsters/blob/407536444934ac7d78f4ce1c18f228e3891a8663/extras/github.rb
- https://github.com/lobsters/lobsters/blob/407536444934ac7d78f4ce1c18f228e3891a8663/spec/extras/github_spec.rb
- https://github.com/lobsters/lobsters/blob/407536444934ac7d78f4ce1c18f228e3891a8663/Gemfile
- https://github.com/lobsters/lobsters/actions/runs/39975413405
- https://github.com/lobsters/lobsters/actions/runs/38323119585
- https://rubygems.org/gems/cgi/versions
- https://www.ruby-lang.org/en/news/2025/12/25/ruby-4-0-0-released/
- https://github.com/lobsters/lobsters/issues/2263
