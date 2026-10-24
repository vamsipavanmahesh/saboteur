# MANIFEST.sha256 coverage and history

Regenerated 2026-10-24 for the batched recovery checkpoint. Command, run from field-runs/:
    find . -type f ! -path ./MANIFEST.sha256 -print0 | sort -z | xargs -0 sha256sum | sed 's# \./# #' > MANIFEST.sha256
Verify with: sha256sum -c MANIFEST.sha256
Coverage: every file under field-runs/ except MANIFEST.sha256 itself (a file cannot contain its own hash). No other exclusions. MANIFEST-NOTES.md is covered, so a later edit to this note changes its entry.
Historical note: the manifest in commit a8dc67efe0f492760df865871289361a87eea54c was NOT current. Checked against that tree, 47 of 856 entries failed by hash mismatch and 10 entries pointed at files that do not exist in the tree. The earlier manifest is not claimed verified. It is replaced here, and the old version stays in git history.
