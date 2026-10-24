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
