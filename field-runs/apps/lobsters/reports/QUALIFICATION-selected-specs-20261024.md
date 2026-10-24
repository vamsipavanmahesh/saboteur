# Qualification: all Lobsters PR replay scores are selected-spec scope (2026-10-24 07:33 IST)

Producer-disclosed CI-flow deviation, recorded on receipt: the PR
trees built a SELECTED-SPEC coverage map (the inferred spec files for
each PR's changed subjects) instead of restoring the pinned
whole-suite map as the requested CI flow would. The source
whole-suite map exists but was not consumed by the PR runs.

Publisher corroboration from the logs on this branch:
- pr2231, pr2156, pr2090, pr2204 replay logs each carry "building
  coverage map (runs the selected specs once)" and "spec inference:
  N spec file(s)" (3, 1, 2 and 1 spec files; 44, 1, 35 and 81 tests).
- The tool line "survivors unconfirmed: no whole-suite coverage map"
  appears exactly in the stages that produced survivors: pr2156 (1)
  and all five pr2204-family logs (serial, det1, det2, jobs2,
  jobs2-repeat). Stages with no survivors (pr2231, pr2090) and the
  0-mutant stage (pr2182, no mutation phase) do not emit it; map2 was
  truncated before scoring.

Consequences for reading the published evidence:
- Every serial, parallel and determinism score published this window
  is a SELECTED-SPECS result, not the full requested CI flow.
- Survivors remain UNCONFIRMED (tool label): a whole-suite map might
  show other tests covering them.
- The full protocol is NOT complete; no end-to-end CI-equivalent
  claim is made or implied.
- Kill/survivor verdicts, parity and determinism zero-diff facts
  stand as measured within the selected-spec scope. Original results
  are retained; no silent rerun replaces them.
