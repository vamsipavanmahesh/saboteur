# Supported base-map restore receipt - PR #2204 v2 replay
- saboteur: version 0.12.3 (gemspec verbatim), source SHA 6f87ccc98377bf0c23f3cf409006f0464c2aa67c, built-gem artifact (sha256 7f5b8949bce9bda19a584c079631d3b76ad37e700935285b550b7bb1c30689fa)
- base SHA: 8f1b50061e5ef0b88ddbadc675395f7b5cf4eb76 (base tree, ruby 4.0.0, EX-1 active, baselines 851 examples 0 failures)
- head SHA: ed722e449227b39ab6268f4260aaa66df95275bd (merge commit)
- cache artifacts restored (exactly 3): coverage-76ba0df91556eb663d67c4ea3d31f6e9f3c69508d00c3450c44595c3fbcdd431.json, inputs-76ba0df91556eb663d67c4ea3d31f6e9f3c69508d00c3450c44595c3fbcdd431.json, whole-suite-map-v2 (pointer content = 76ba0df9..., 64-hex format verified)
- prefix-match verification: committed Gemfile.lock + saboteur config identical base..head (git diff empty); saboteur 0.12.3 Gemfile addition replicated identically in base tree (Gemfile+lock copied from head); db schemas identical (git diff base..head -- db/ empty)
- v2 result: 19k/3s score 86.4% exit 1 wall ~33s; saboteur confirmation: "3 unconfirmed - whole-suite map covers none of the edited lines of 3 survivors, stay counted"; fake-kill structured check CLEAN, rejectedKills=0
- OBSERVED finding (scoped): for THIS PR, base-map restoration via the supported flow leaves these 3 survivors (all on story.rb:777, a line this PR edited) unconfirmed. No universal claim about all edited-line cases is made here.
