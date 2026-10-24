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
- Worker diagnosis (not established as the sole cause under the unsupported relocated runtime): core/lib/spree/testing_support/dummy_app.rb:140 defaults active_storage.variant_processor to :vips; the sandbox has no system libvips, so the vips transformer lookup yields nil and `.new` is called on nil. Solidus CI installs libvips; the README core-suite instructions do not mention this dependency (documented-flow gap F-ENV-1).
- The app's own escape hatch (ACTIVE_STORAGE_VARIANT_PROCESSOR=mini_magick, same file:140) does NOT clear them: 19 examples, 6 failures, different error (ActiveStorage UnsupportedImageProcessingMethod: saver - Solidus passes a vips-only `saver:` transformation). Recorded as fact; not used as a workaround.

## Status by stage
environment done; baseline done (exit 1, baseline-red candidates above); documented_flow/map/pr_replays/parallelism/determinism not_done pending verified saboteur 0.13.0 SHA; triage/kills assigned to a fresh-context triager (not this agent).



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

