# New main-pinned Lobsters run: environment and scope

Saboteur0.12.3, source6f87ccc98377bf0c23f3cf409006f0464c2aa67c. App pin407536444934ac7d78f4ce1c18f228e3891a8663. This file supplements, not overwrites, historical apps/lobsters/ENV.md.

## Approved field-only exclusion, October24 at06:52 IST

Exclude only spec/features/user_administration_spec.rb through saboteur's rspec_args setting. No app spec/file edit is approved. Record this exclusion and its reason in every affected future measurement/report row.

Reason: banning-email test is red on Lobsters main at40753644 independently of saboteur; no selected PR touches it. The suggested relation to Lobsters issue2263 is unverified, not an established cause. Corrected full baseline913examples/1failure/exit1 and raw log preserve the independent failure.

The prior map attempt at jobs4 and all pre-approval baselines remain historical controls without this exclusion. Do not retroactively label those rows excluded. No post-approval map/replay result is present in this snapshot.

## Execution controls

Serial reference first: map and five PR replays with explicit --jobs1. Then one replay with --jobs2 for per-mutant comparison. Never use jobs4 for future runs on this2CPU/1.9GB machine. New PRs must use each tree's actual Ruby requirement; first five readiness attempts failed because Ruby4.0.9 did not match Gemfile4.0.0.

D-ENV-1: renamed Ruby's stdlib cgi.rb shim and cgi/ directory aside in writable Ruby4.0.9 and4.0.0 trees; RUBYLIB otherwise retained for the relocated runtime. Before/after probes prove CGI.parse false-to-true and load from cgi0.5.1 gem. Bare require outside the app bundle may now fail. No app/spec code changed for this environment correction.

Doctor: Landlock ABI2 cannot provide ABI3 truncate restriction; hazard guard and canary fallback. Passed command does not establish full safety compatibility. Memory values use producer peak-child RSS, not summed whole-host/service usage.

Hard stop:09:46:01IST October24,2026. Lobsters all stages, including independent survivor/kill checks, before Chatwoot. New Solidus execution out of scope.
