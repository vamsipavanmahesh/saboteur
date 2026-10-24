# Chatwoot bug-study candidate selection (frozen 2026-10-24)

- pr-ledger-961-raw-api.json: raw GitHub API pull data for the 961 PRs in the frozen window
  (collection HEAD 98a9ed710ad7334b07e96ca6c1da0b7e8ebc686a; window ends 2026-04-24T00:00:00+05:30).
- pr-ledger-961-classified.json: per-PR classification - number, title, commit, merged_at,
  files_touched, bug signals, eligibility (961 rows; 728 eligible, 41 unresolved, 192 ineligible).
- bug-candidates-eligible-20.json: first 20 eligible by merged_at DESC under the frozen ANY-3
  signal rule. Note: #16385 ("fix(deps)...") eligibility is NOT a verified bug; verification pending.
- Classifier query and per-bucket ID lists are held in the producing environment's work records.
