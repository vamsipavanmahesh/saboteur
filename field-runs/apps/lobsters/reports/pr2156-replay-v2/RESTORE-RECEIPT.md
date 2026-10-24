# Supported base-map restore receipt - PR #2156 v2 replay
- saboteur: version 0.12.3 (gemspec verbatim), source SHA 6f87ccc98377bf0c23f3cf409006f0464c2aa67c, built-gem artifact (sha256 7f5b8949bce9bda19a584c079631d3b76ad37e700935285b550b7bb1c30689fa)
- base SHA: 9a773eac0b49fd86b16585ad503de9a51919c496 (base tree, ruby 4.0.0, EX-1 active, baselines 859 examples 0 failures)
- head SHA: d9998c2555317db7b3cb9a159ef7878ff993ab78 (merge commit)
- cache artifacts restored (exactly 3): coverage-37d91f0473e9e5337aefca138cf8fb1c4f38e2afef99231f6b2716a71917f493.json, inputs-37d91f0473e9e5337aefca138cf8fb1c4f38e2afef99231f6b2716a71917f493.json, whole-suite-map-v2 (pointer = 37d91f0473e9e5337aefca138cf8fb1c4f38e2afef99231f6b2716a71917f493, 64-hex verified)
- prefix-match verification: committed Gemfile.lock + saboteur config identical base..head (git diff empty); Gemfile+lock copied from head so bundler state matches; db schemas identical (git diff base..head -- db/ empty)
- v2 result: 6k/1s score 85.7% exit 1 wall ~15s; confirmation: "1 unconfirmed - map covers none of the edited lines of 1 survivor, stays counted"; fake-kill structured check CLEAN, rejectedKills=0
- OBSERVED finding (scoped): same shape as #2204 - the survivor (settings_controller.rb:51) sits on a line this PR edited; base-map restoration via the supported flow leaves it unconfirmed. Observed for these two PRs; no universal claim.
