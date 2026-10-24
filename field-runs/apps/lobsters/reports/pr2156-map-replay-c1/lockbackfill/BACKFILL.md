# 2156 bounded-lock backfill (post-hoc captures, capture times stated)
- Captured 2026-10-24 10:25:30 IST, AFTER the row completed (M boundary 10:18:21, R exit 10:22). The lock file itself has been byte-identical since 10:04:42 (pre-launch bounded install; mtime verifiable on disk); no bundler operation touched this tree during or after the row.
- era lock: git HEAD bytes (sha256 9efe9531313688cd7da2cf15a03cbbf900955866e9d8a070a35b65b43b288d8a) - attached Gemfile.lock.era-9efe9531
- bounded lock (as-run for BOTH M and R): sha256 6b3775bd1acb0353b3a8d8b564ce18072d6f4a9a8b654d0d79138a4469da2e5b - attached Gemfile.lock.bounded-6b3775bd
- version diff: lock-diff-era-to-bounded.txt - ONLY +fiddle (1.1.8), +saboteur (0.12.3), +prism dep line, +DEPENDENCIES lines; zero version changes to any pre-existing gem
- bundle list digest (post-hoc 10:25:30): in bundle-list-digest-posthoc.txt; saboteur version (post-hoc): saboteur-version-posthoc.txt
- headmap2.sh preamble captured for this row in logs/pr2156-map-c1.log (runner hash, HEAD, start, PGID, T0); LOCK/BUNDLE_LIST/SABOTEUR_BIN preamble fields exist only from headmap3.sh (row-4 onward)
