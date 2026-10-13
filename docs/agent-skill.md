# Saboteur for AI coding agents

`saboteur agent-skill` prints the block below. Paste it into your AGENTS.md or CLAUDE.md.

<!-- agent-skill:start -->
## Mutation testing with saboteur

After you change covered Ruby behavior or its specs, and RSpec is green, run saboteur
on your diff before you say the work is done:

```
saboteur run --agent --since origin/main
```

Read the JSON on stdout. `status` is `complete`, `partial` or `not_applicable`.
The exit code is strict: 0 means complete and clean, 1 means a survivor needs
review, 2 means a bad command or config, 3 means the run was incomplete or failed.

To preview cost without booting the app or running tests, use `saboteur run --dry-run`.
`--list-operators` shows names and tiers; `--operators arithmetic,comparison` restricts the run.

When a mutant survives:

1. Pick one live survivor from `findings.shown`.
2. Add the smallest test that checks the observable behavior the mutant changed.
   A finding's `testHint`, when present, says where to look (for a comparison, the
   `case` of operands that separates the two). It is a suggestion; the survivor
   can also be an equivalent mutant.
3. Replay it with the command in `next.replay` (it uses the recorded seed) and
   confirm the mutant is now killed.
4. Run the diff again. Repeat until the exit code is 0.

Rules:

- Report `partial` and `not_applicable` results as they are. Say what had no
  coverage or was capped; do not call an incomplete run clean.
- Never change production behavior only to kill a mutant.
- Never add survivors to the ignore list yourself. Ask the owner.
- Run `saboteur help` for every command, option and exit code.
<!-- agent-skill:end -->
