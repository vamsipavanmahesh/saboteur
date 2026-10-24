# PR2157 independent survivor and kill checks

Era merge8e46ece70245f834e4f43a5563cd9b90efc6e1d0, parent
d9998c2555317db7b3cb9a159ef7878ff993ab78, public lobsters/lobsters.
Source report is retained unchanged. This verifies every one of its six
survivors and five kills, not any whole-suite map or other study row.

## Environment and exact mutations

A separate disposable checkout was created at the exact era. The era-original
lock was used with `bundle install --local`; final diff adds fiddle1.1.8 and
saboteur0.12.3 only, preserving other dependency versions and checksums.
Installed immutable built artifact SHA256 is
7f5b8949bce9bda19a584c079631d3b76ad37e700935285b550b7bb1c30689fa,
from source6f87ccc98377bf0c23f3cf409006f0464c2aa67c. Shared previously
verified Ruby4.0.0/Linux native dependencies were reused; per-checkout loaded
proof is included. The shared installed238 packaged files previously matched
both immutable artifact and pinned source. No path-source substitution or
checksum bypass. Runtime details in provenance/runtime-env.sh. Local DB was
prepared from unchanged database.yml.sample; no exclusions were applied.

All11 mutation IDs were independently regenerated with the installed pinned
source's SubjectFinder/Builtin generator and compared by full digest. Their
exact byte edits and original spans are recorded in exact-edits.json. This is
important: multi-edit removals have a display replacement of ` | ` in JSON;
that string is not a literal replacement to apply over the first location.
extract_edits.rb is the executable extraction procedure. Applied diffs and
mutation.json preserve actual individual edits per case.

## Six survivors: real gaps demonstrated

For each full ID below, all9 original report-recorded executed examples pass
both original and mutant. The added local request spec then passes original,
fails mutant by expectation (not crash), and passes restored original. It
checks rendered HTML's og:image content and article:author URL. This is a local
verification spec, not an upstream contribution or product change. Each case
contains raw5 runs, argv, example IDs, JSON failures, logs and restoration hash.

- 5cacdbc3d0bc508e: removes article:author element plus comma. New expectation
  fails because no article:author metadata contains Routes.user_url(story.user).
- 1f1092204c9a42bb: removes og:image property pair plus comma. Meta cannot be
  found by its required property, so actual nil differs from image URL.
- 43dda9ad5517cd5d: changes og:image property string to empty. Same missing
  property assertion failure.
- 605c15816c32610f: removes image element plus comma. Same missing image
  assertion failure.
- bea8f4593231093a: removes image content pair plus comma. Empty rendered
  content differs from expected image URL.
- 3aa0bb7820610094: removes entire meta_tags assignment. Missing image metadata
  fails the new expectation.

These are reachable, observable output changes, not equivalent mutants or
setup noise, and the report-recorded existing examples miss them. No fresh
whole-suite execution was done: this does not prove no unexecuted suite example
could already kill a survivor. Map completeness remains separately unresolved.
No false-survivor classification was asserted from a map label alone.

## Top-ranked finding

The raw saboteur.findings.order first live unignored ID is
5cacdbc3d0bc508e, not selected by this review. It is included in the real-gap
proof above: original HTML has the local author URL, actual mutated HTML lacks
it, and the added expectation kills it. Other survivors in the same metadata
region also have individual evidence, not an assumed group verdict.

## Five kills

Every case has original selected example PASS, mutant FAIL, restored PASS,
exactly1 example each. Tests come from raw killedBy -> testFiles mapping.

- 15108fd76959c185 body_nil: ActionView::Template::Error caused by nil story
  receiver is_gone? at app/views/stories/show.html.erb:2. Exception kill.
- ebd733eb8d8ee4b9 body_raise: RuntimeError stories_controller.rb:145.
  Exception kill.
- 8eb0cb142d0a1d02 argument_removal: ArgumentError, zero args to
  Routes.story_image_or_logo_url at extras/routes.rb:44 via controller189.
  Exception kill.
- cc4cd6ceffdeeea4 statement_removal: existing request expectation at
  stories_spec.rb:209 fails, expected HTTP200 got404. Assertion kill.
- 87223da944e9951b statement_removal: existing request expectation at
  stories_spec.rb:184 fails, expected HTTP200 got404. Assertion kill.

All five observed cause classes match the report classification: 2 assertion,
3 exception; no DB/infrastructure failure in these failing example bodies.

## Limits and restoration

App controller bytes are restored after every case, with matching hashes and
empty final-app.diff. New local verification spec remains as an explicit added
artifact; no original specs changed. An execution time limit interrupted the
first survivor batch after three completed receipts. State was inspected, the
controller explicitly restored, and only unreceipted cases were resumed. The
remaining three have complete independent receipts. No partial case is counted.
No product edits, upstream writes, map rebuild or mutation engine replay.

Classification totals here describe six checked reported survivors, not a
population-wide noise estimate. Broader protocol validity and publication are
outside this packet. Source URLs:
https://github.com/lobsters/lobsters
https://github.com/vamsipavanmahesh/saboteur
