# Chatwoot recovered sandbox-era scripts (2026-10-24)

These four scripts were recovered byte-for-byte after a sandbox reset. They are historical sandbox-era artifacts, not GitHub-Actions-ready and not a verified workflow. No map or replay route is implied.

| file | sha256 |
|---|---|
| run-prepare.sh | a3a3743ba4784d2ddb79ad9c4943d314b832896166adafa1edaa1b2d7f885720 |
| run-map3.sh | 76fbf2147f8f7d9b5839eb1874b22e5e59653359e0fbb46af848d8880ff3ec50 |
| run-replay-pr.sh | 061b9494ebed059c439e684a88b973836351a6c3ceb7bbbaafa5c71eada6da3a |
| map-boundary-watch4.sh | 87a686bcb246ba526bfe1aa9c2a5074b39742462aaaa661749269d169dadb711 |

Known limits, left unedited so the bytes stay exact:
- run-map3.sh line 28 and run-replay-pr.sh line 49 are comments/strings that name saboteur artifact sha256 57ac8099a6f78ff713d6f361ef7e14632ca1676acdec02d15adcab46f0ca0dd4. That artifact is superseded. The replacement gem has sha256 7f5b8949bce9bda19a584c079631d3b76ad37e700935285b550b7bb1c30689fa and was compared against the source pin 6f87ccc98377bf0c23f3cf409006f0464c2aa67c: all 238 gemspec files (235 lib/exe files plus 3 docs) byte-identical, no extras. It is a replacement with change provenance, not the identical 57ac container. The old hash stays as historical text in the earlier decision.
- run-map3.sh and run-replay-pr.sh use a Gemfile source of file:///home/sandbox/fieldruns/local-gems, a path that exists only in the lost sandbox. It is not runner-compatible. A hosted route would need a reviewed adapter and the actual runner checkout path or artifact.
- Each script contains the CE strip step `rm -rf enterprise spec/enterprise` (prepare: after the pnpm step and before the database step; map: after TREE_CHECK; replay: after checkout).
