# Ledger v3 corrections (originals preserved in noise-ledger-v3.csv)

- 2182: app_lib_ruby_count corrected 1 -> 2 (story.rb + user.rb per merger live API verification f6883603, 08:28). Discrepancy preserved: git first-parent diff of the squash commit afd505e4 shows only app/models/story.rb (+ spec/helpers/users_helper_spec.rb); API PR-files shows story.rb + user.rb + spec. Unresolved git/API difference; saboteur replay operates on the git first-parent diff (base e5fda597), both recorded. No eligibility impact.
- 2078: git first-parent diff = 13 app/lib rb files vs API 3 (merger) - genuine diff-base difference, below cutoff, both recorded.
