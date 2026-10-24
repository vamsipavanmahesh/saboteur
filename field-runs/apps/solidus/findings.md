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
