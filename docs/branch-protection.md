# Branch protection settings for `main`

Apply these in the repository settings yourself; agents do not change
repository settings. Settings > Rules > Rulesets > "main exact-head gates"
(ruleset id 24879445, already active).

## Required status checks

The ruleset already requires these 23 contexts (strict: exact head):

- panel/head-gate
- lint
- dry-inflector (class_eval), dry-inflector (nesting),
  tty-color (class_eval), tty-color (nesting)
- dogfood
- signoff
- Ruby 3.3 / linux / shard 1-3, Ruby 3.4 / linux / shard 1-3,
  Ruby ruby / linux / shard 1-3, Ruby ruby / macos / shard 1-3
- Ruby 3.4 / LANG=C / shard 1-3

Add the two harness checks so every pull request runs them:

- `acceptance` - fast tier of the acceptance suite
  (.github/workflows/harness.yml)
- `claims-check` - every CHANGELOG/README behavior claim carries a live
  (e2e:) reference (same workflow)

Also add `acceptance-guard` (.github/workflows/acceptance-guard.yml): a pull
request touching acceptance/expected.yml always fails; a pull request
touching other acceptance/ files fails only from an agent task branch
(p<N>-..., the harness naming convention).

Known gaps in the current list, found 2026-10-23 and worth fixing in the
same pass:

- `panel/head-gate` is required but the workflow that produces it has been
  invalid since 2026-10-17, so the status never posts; every merge since
  used the admin bypass. Fix .github/workflows/panel-gate.yml first
  (issue #1324), otherwise the required set stays unsatisfiable.
- The list under-covers today's CI matrix: CI runs 4 shards per Ruby leg
  and more macOS legs than the required 3+3. Decide whether to require the
  full current matrix.

## Code owner review

Settings > Rules > pull_request rule: enable "Require review from Code
Owners". .github/CODEOWNERS gives @vamsipavanmahesh ownership of
acceptance/ and the enforcement machinery (claims checker, rake tasks,
guard workflow, PR template, AGENTS.md, RELEASING.md).

Honest limit: agent pull requests are opened from your own account, and
GitHub does not let an author approve their own pull request, so a
CODEOWNERS review requirement cannot be satisfied by the same account that
opened the PR. The real mechanical blocks for acceptance/ are the
`acceptance-guard` check above plus your own habit of landing expectation
updates as direct commits. Treat CODEOWNERS review as a second pair of
eyes for outside collaborators, not as agent-proofing.

## Admin bypass

Your PAT is a ruleset bypass actor (RepositoryRole, always). That means
any required check - including the harness checks - can be overridden by
you, and nothing in this repository can prevent that. The harness makes
changes loud and recorded; the decision to honor a red check stays human.
