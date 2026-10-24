# New Lobsters run: evidence snapshot 06:49 IST, October 24, 2026

Source: 6f87ccc98377bf0c23f3cf409006f0464c2aa67c; gem0.12.3.
App: 407536444934ac7d78f4ce1c18f228e3891a8663.

Raw received logs are copied without edits. Producer measurement evidence_paths are relative to the original execution root; logs/ paths resolve inside this snapshot, while producer lobsters/ paths refer to its app checkout. config-saboteur.rb is the received generated config. Original bundle-install/generator/doctor/map measurements are now retained beside enriched records. The original map record carried status=null and no evidence paths; its enriched copy adds blocked status and received log paths without changing command, times, identity or numbers.

Stage state: documented flow partial/idempotent install check, first map BLOCKED(exit5,49.66s,426384KiB; no mutants); corrected full baseline913examples1failure(exit1,41.93s); PR replay/parallelism/determinism/independent survivor and kill checks NOT STARTED. Exclusion decision pending. No mutation scores exist.

The generator preceded the built-gem install. Do not treat it as built-artifact generator proof. Artifacts now include the actual504320-byte gem (SHA256 independently matched to7f5b8949bce9bda19a584c079631d3b76ad37e700935285b550b7bb1c30689fa), source commit inspection and an empty lib/exe diff file. The diff command/exit status and a source-cleanliness read are not in that file, so no stronger independent claim is made. No separate build log survived; none is fabricated. New PR replacement2182 qualification is now included as pr2182-qualification.json: merge afd505e45084f7c9fd504ae8968886eee102c961, parent e5fda5974779549267ac25fdf4855fdd0cf0101b, September14 merge. Its three changed files are app/models/story.rb, app/models/user.rb and spec/helpers/users_helper_spec.rb. Five new PR bundle readiness logs are included for2231/2204/2182/2156/2090. Each records Ruby4.0.9 versus Gemfile4.0.0 mismatch. No exit/time measurements were provided for these attempts; no readiness success or replay mutation result is claimed. Historical PR selections remain separate and do not qualify the new run by themselves.

See ../../REPORT-update-20261024-0649.md for current conclusions and explicit environment deviations. Historical app evidence remains under ../../apps/. No prior baseline or mutation exit status was changed.
