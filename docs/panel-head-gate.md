# Exact-head panel gate

This gate enforces three named lens attestations, 13 successful CI/DCO jobs,
author-matching DCO trailers, an up-to-date main ancestor, and unchanged gate
policy. It does not prove review quality or independent execution of tests.
All three lenses currently publish through GitHub user ID 1875074
(`vamsipavanmahesh`). This is one trusted publisher, not three independent
people. Anyone controlling that account can supply all three markers.

## Marker contract

Place this canonical JSON block at the **very start** of a new PR issue comment.
Use exactly two-space indentation, LF newlines, the keys below in any order,
no extra keys, no duplicate keys, no trailing commas, and no abbreviated SHA.
JSON must be identical to `JSON.stringify(value, null, 2)`. Human-readable
review discussion may follow the block. Do not put it in a quote or nest it
inside another code fence. The parser does not infer approval from prose.

```panel-verdict
{
  "schema": 1,
  "lens": "principal",
  "head": "0123456789abcdef0123456789abcdef01234567",
  "verdict": "APPROVE",
  "scope": "Full PR diff and related contract paths",
  "independently_run": [],
  "author_reported": [
    "Full suite and dogfood; not independently rerun"
  ],
  "uncertainty": [
    "Static review only; runtime evidence comes from required CI"
  ],
  "prior_findings": [],
  "blockers": []
}
```

- `lens`: `principal`, `architect`, or `qa`.
- `head`: exact current 40-character lowercase hexadecimal PR head SHA.
- `verdict`: `APPROVE` or `CHANGES_REQUIRED`.
- `scope`: a nonempty string describing files/delta/full-PR scope.
- All five evidence fields are arrays of nonempty strings (empty arrays allowed).
- `independently_run`: exact commands, environment and results actually run.
- `author_reported`: claims not independently verified.
- `uncertainty`: unresolved limits, not boilerplate assertions of confidence.
- `prior_findings`: resolution of each prior finding, with locations/evidence.
- `blockers`: file/location plus failing case/reproduction and required fix.
  APPROVE requires an empty array; CHANGES_REQUIRED requires at least one blocker.

New pushes and update-branch/rebase require new exact-head attestations.
The latest updated comment for each lens wins (ID breaks timestamp ties),
but publish new comments rather than editing verdicts.
Any malformed trusted marker fails the gate, even when older than a valid one.
Untrusted publishers cannot approve or revoke. Lens-specific publisher IDs are
allowlisted in `script/panel-gate/policy.json`; names alone are not identities.
An edited older blocking verdict takes precedence by update time. Editing or
deleting a marker records a persistent PR-scoped revocation on the fixed trusted-main
commit anchor in policy. It applies across head pushes, including removal of a
stale-head blocker. A replacement must be a new comment with an ID above the
observed comment high-water mark AND a creation time strictly after GitHub
recorded the revocation. Same-second comments fail conservatively; publish again
in a later second. Editing or restoring an older comment cannot clear revocation.
Editing/deleting a malformed marker requires
fresh comments for all lenses. Do not edit/delete review history; publish a new
superseding verdict. Tombstones remain even if the deleted marker is restored.

Before reading comments for a high-water refinement, the event handler writes
one atomic PR-scoped revocation intent (one lens, or all lenses for malformed
markers) to the fixed anchor, plus a redundant current-head failure latch.
Either record blocks old approvals by its server creation epoch. A failed
refinement or comments read cannot erase the intent. Before posting pending,
verification promotes a head-only latch to the fixed anchor with its original
epoch; promotion failure fails closed. Fresh attestations clear the condition,
not the stored history. This prevents later sweeps from treating a transient
ledger failure or partial malformed-marker write as a clean approval.

## Trust and execution boundary

`panel-gate.yml` runs trusted main code on issue-comment events, CI/DCO workflow
run events, main pushes and manual dispatch. It does not use pull_request_target,
run PR code, download artifacts, restore caches, install dependencies, or place
comment content in shell commands. Checkout is pinned, credentials are not
persisted, and permissions are contents/PR/issues/actions read plus statuses
write. No repository secrets are used. The verifier fetches PR facts afresh,
checks protected-file Git blob IDs against base, validates complete paginated
comments/commits/jobs/runs, and posts `panel/head-gate` on the actual PR head.
API errors fail closed; if it cannot publish a result, a missing/pending gate
is not approval. Protected paths include the entire workflow directory (including additions),
CI, DCO, verifier, policy, tests,
Action manifest/launcher, integration manifest/configs, mutation config and ignore file.

CI's pull_request workflow is allowed to execute untrusted code with read-only
permissions. The trusted verifier never executes that code. A completed CI run
must match the exact head, PR number, repository and workflow path, with exactly
12 expected successful jobs; DCO must have exactly one successful signoff job.
Newest run ID and its latest attempt win. Immediately before success, the verifier
reselects the newest required runs, refreshes their latest attempts and checks
all jobs again. Run IDs, attempts, job IDs and green conclusions must match
the initial validation. It also rereads the PR-scoped revocation ledger; any
change during verification fails conservatively, even if new approvals exist.
Skipped/neutral jobs do not pass.
DCO is also checked from commit metadata, with exact author-matching trailer
lines; the existing policy exempts merge commits.

Current main must be an ancestor of head. After another PR merges, update/rebase
this PR, rerun all checks, and re-review that new SHA. This gives a conservative
serialized integration policy without pretending API PR base objects record
which historical merge candidate a run tested.

## Limits that settings and workflow code do not remove

- This is an operational barrier for the current owner-published panel, not a
  cryptographic or three-person attestation. Same-account lenses share trust.
- GitHub comment/rerun events and status updates are asynchronous. A prior
  success can remain visible until revocation is processed. Concurrency is
  serialized with `queue: max` (up to 100 pending runs), and every wake sweeps
  all open main PRs. Queue overflow cancels additional runs. The default
  single pending slot is deliberately not used: it replaces older queued events.
  An edit/deletion event lost before its tombstone is written
  cannot be recovered from the comments API. Never delete verdicts; supersede
  with CHANGES_REQUIRED, wait for the failing gate, and only merge after a fresh
  completed gate. The website merge lane must check newest comments, required run IDs/latest
  attempts/jobs and fresh gate completion as well. GitHub offers no atomic
  snapshot or compare-and-set across these APIs: a rerun, comment edit/deletion,
  push or revocation can occur after the final reads but before the success
  POST (or after it). Rechecks narrow this window; they do not eliminate it.
  The fixed ledger anchor must remain unchanged across normal policy updates;
  replacing it requires an explicit migration, not clearing review history.
  Status-history pagination limits and ledger API failures fail closed.
  Redundant intent/head latches tolerate one failed storage write, not total
  write failure. Retry a failed revocation event after API recovery. If only
  the head latch persisted, recover it before any head rewrite/force-push; an
  abandoned head can otherwise hide that fallback. No comments-only sweep can
  recover a deleted event that never reached either durable write. Queue overflow
  remains a delivery-loss boundary, not a solved durable queue problem.
- An administrator can change rules/settings. Other write-capable workflows or
  credentials could spoof the same commit-status context. Requiring all 13
  native GitHub Actions checks helps, but Actions source binding does not
  distinguish one workflow from another. Use a dedicated GitHub App, installed
  with least privilege and selected as the required check source, for a stronger
  boundary. No such App is provisioned by this patch.
- Test scripts/specs themselves may still be weakened outside the protected
  paths; semantic panel review remains necessary. This verifier is not an
  isolated external test oracle.
- Legitimate gate/CI-policy updates fail deliberately. Maintain them through
  explicit owner-approved, panel-reviewed maintenance, with a narrowly scoped
  temporary ruleset change and immediate restoration/readback. Do not add a
  magic comment or contributor-controlled bypass to this script.

## Deployment and bootstrap

1. Review and merge this bootstrap patch using the existing manual three-lens,
   full-green CI/DCO procedure. A gate existing only on a PR branch is not live.
2. Verify main contains these exact files. Open an ordinary non-policy-change
   PR and publish three canonical markers, then run CI/DCO. In Actions, run
   `Panel head gate` **from main**, with that PR number. Manual dispatch sweeps
   all open main PRs; the input is validated for operator clarity.
3. Confirm `panel/head-gate` is successful on that PR head and references the
   trusted main workflow run. Inspect the log and all 13 native checks.
4. Apply the main ruleset below. Test it with stale SHA, CHANGES_REQUIRED,
   missing lens, non-green job and protected-policy-change cases before relying
   on it. Tests in this patch are local/fake-API validation, not a live Actions
   deployment test. Do not claim enforcement until ruleset and real run readback.
5. Existing prose reviews are not grandfathered. Obtain new canonical markers.

## Website settings runbook (do not apply from code)

Audit on October 11, 2026: Branches says "Classic branch protections have not
been configured"; Rulesets says "You haven't created any rulesets". Default
branch is main. Those observations mean CI/DCO are not currently required rules.

Observed settings pages:
- https://github.com/vamsipavanmahesh/saboteur/settings/branches
- https://github.com/vamsipavanmahesh/saboteur/settings/rules

Settings > Rulesets > New ruleset > New branch ruleset:
1. Name `main exact-head gates`; Enforcement status **Active**.
2. Bypass list: empty. Do not give the owner/administrator a routine bypass.
3. Target branches: include the default branch (`main`); no exclusion.
4. Restrict deletions; block force pushes.
5. Require a pull request before merging. Native approval count **0** for the
   current one-account panel, whose approvals are issue comments. Do not require
   three native reviewers: the author cannot approve their own PR and one
   identity cannot satisfy three independent reviewers. If independent accounts
   are later added, separately enable required native reviews and dismiss stale
   approvals when new commits are pushed; that setting never validates comments.
6. Require status checks to pass. Require branch up to date before merging.
   Add `panel/head-gate` and every check listed below. Use GitHub Actions as the
   source for native checks where the UI supports it. The status context may
   show its actual publishing App source after bootstrap; verify, do not guess.
7. Do not enable merge queue yet. Do not enable linear history yet: it is a
   history-format preference, not a review gate, and current merge commits are
   allowed by DCO. Requiring squash/rebase would need a separately agreed merge
   strategy and DCO validation of the resulting commits.
8. Save, reopen, visually inspect Active targeting main, empty bypass list and
   all required checks. Verify the PR merge box actually blocks a failing gate.

Expected native job contexts (confirmed from live Actions jobs API):

```
Ruby 3.3 / ubuntu-latest
Ruby 3.3 / macos-latest
Ruby 3.4 / ubuntu-latest
Ruby 3.4 / macos-latest
Ruby ruby / ubuntu-latest
Ruby ruby / macos-latest
lint
dry-inflector (class_eval)
dry-inflector (nesting)
tty-color (class_eval)
tty-color (nesting)
dogfood
signoff
```

GitHub may present workflow-qualified display labels; select the corresponding
actual contexts after a real run. Do not select a merely similar text label.

Merge queue is not shipped here. Check account/plan availability explicitly;
GitHub documents availability for public organization repositories and eligible
private organizations, while this repository is user-owned. Even if available,
every required workflow would need `merge_group`, and DCO/dogfood/panel mapping
must cover the exact merge-group candidate. Merely adding that event is not a
complete implementation. Serialize merges and update/retest against main now.

## Local tests

```
node --test script/panel-gate/verify.test.cjs
```

Tests cover spoofed/short/stale SHAs, malformed/noncanonical/duplicate markers,
wrong publishers, wrong lenses, latest blockers and edited older blockers,
deletions/tombstones, skipped/neutral/duplicate/missing jobs, DCO mismatches,
wrong run head, changed policy, stale main and a head change during verification.
Regression tests cover low-ID edited blockers, stale-head edits/deletions through
the event handler, cross-head/PR-scoped persistence, same-second cutoffs, reruns
becoming pending, newer runs/green attempts, failing/replaced jobs, new revocations
and ledger failures during the final recheck. Failed write/read regressions
invoke verification on later recovered-API sweeps, including all-lens malformed
revocations, original-epoch latch promotion and fresh-attestation recovery. CI oracle path changes fail closed.

## Sources

- https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows
- https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target
- https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets
- https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue
- https://docs.github.com/en/pull-requests/concepts/deploying-code
- https://docs.github.com/en/rest/actions/workflow-runs
- https://docs.github.com/en/rest/commits/statuses


Concurrency queue behavior: https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency
