# Executed gem artifact vs pinned source - byte-level audit (2026-10-24 09:13 IST)

Claim audited: the saboteur gem executed in the PR 2231 canary (map job M) is the pinned source, not the registry release.

## Method
- Executed artifact: vendor/cache/saboteur-0.12.3.gem, sha256 7f5b8949bce9bda19a584c079631d3b76ad37e700935285b550b7bb1c30689fa (byte-identical to the installed copy per the worker's 09:12 packet).
- Pin: saboteur main 6f87ccc98377bf0c23f3cf409006f0464c2aa67c (0.12.3).
- Every file in the gem's data.tar.gz (238 files) compared byte-for-byte against the pin's git blobs; every lib/ and exe/ path in the pin checked for presence in the gem.

## Result
- differs=0, not-in-pin=0, missing-from-gem(lib+exe)=0. The executed bytes ARE the pinned source.
- The registry release 0.12.3 (Gemfile.lock CHECKSUMS sha256=234ee503f80b9d532fd6fd3607843d06bc4e4d2a7c3c61340560fdbe10e3fc03) is NOT what executed; the difference between a registry release and a pinned main build is expected pre-release drift, not an incident. The user's 2026-10-24 06:46 instruction requires building the gem from the pinned main and installing that build.

## Reproducibility caveat (carried until the post-R lock fix)
- The as-run Gemfile.lock (Gemfile.lock.pr2231-M-current) records the registry checksum 234ee503..., not the executed artifact 7f5b8949.... Recomputation from the lock alone resolves the wrong artifact. The lock is frozen byte-stable for the canary M/R pair (lock content is a cache key input; changing it mid-pair invalidates the map provenance). After run R completes, the lock is to be regenerated through bundler against the isolated local artifact source so the recorded checksum equals the executed bytes; later era rows then build their maps under the corrected lock.
