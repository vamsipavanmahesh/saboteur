# Contributing to saboteur

## Developer Certificate of Origin

Every commit must be signed off, certifying the
[Developer Certificate of Origin 1.1](https://developercertificate.org/):

```sh
git commit -s -m "Add comparison operator"
```

This adds `Signed-off-by: Your Name <you@example.com>` to the message, which
must match the commit author. A GitHub Action rejects pull requests with
unsigned commits. To fix an existing branch: `git rebase --signoff main`.

## Clean-room rule

saboteur is written from scratch. Do not copy, port or paraphrase source code,
specs or fixtures from other mutation testing tools under restrictive
licenses, and do not read their source while working on saboteur. Public papers
and documentation describing general techniques are fine; add them to
[docs/prior-art.md](docs/prior-art.md).

## What not to commit

No proprietary code, internal URLs, credentials, customer data or business
logic: not in code, fixtures, examples or commit messages. Write fixtures from
scratch.

## Development

```sh
bundle install
bundle exec rspec
bundle exec rubocop
```

Every change needs specs. New source files start with
`# SPDX-License-Identifier: MIT`.

## Governance

saboteur currently has one maintainer. If you depend on it, the bus-factor
plan is: the agent JSON payload and exit codes are stable APIs
([docs/stability.md](docs/stability.md)), the review and design record lives
in `docs/`, and the release process is the CI pipeline every pull request
already runs. A contributor stepping up starts with an open issue or a small
pull request; commit and release access is granted by the maintainer after a
track record of merged changes. If the maintainer is unreachable, the MIT
license keeps a fork viable.

## Pull requests

Keep them small, describe the behaviour change, and add a CHANGELOG entry
under "Unreleased".
