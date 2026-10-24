# Human Essentials recovery checkpoint (2026-10-24)

Status: zero completed study rows, zero verified bugs, doctor unfinished with no verdict (neither pass nor fail). No rates.
New in this directory: PORTABLE-REQUIREMENTS.md, RECOVERY-DECISIONS.md, fresh out-of-scope-inventory.json, fresh snapshot-compat-matrix.json (per-member drift 37 to 88 commits), selection-v3.json (regenerated from the public API plus frozen git ancestry; byte-identical to attempt-3/selection-v3.json).
The attempt-3 scripts (recovered byte-for-byte, already published) are at ../attempt-3/bin/. They use absolute paths and snapshot reuse that need review before any hosted use. Do not treat them as a ready workflow.
The saboteur 0.12.3 gem archive is not committed. It is rebuilt from source pin 6f87ccc98377bf0c23f3cf409006f0464c2aa67c; build it from source, never install the registry gem.
Differences from attempt-3/: out-of-scope-inventory.json and snapshot-compat-matrix.json were regenerated and differ from the attempt-3 copies (both are kept).
