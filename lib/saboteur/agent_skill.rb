# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # The instructions for an AI coding agent, printed by `saboteur agent-skill`.
  # Paste them into AGENTS.md or CLAUDE.md. docs/agent-skill.md carries the same
  # block; a spec keeps the two equal.
  module AgentSkill
    TEXT = <<~MARKDOWN
      ## Mutation testing with saboteur

      After you change covered Ruby behavior or its specs, and RSpec is green, run saboteur
      on your diff before you say the work is done:

      ```
      saboteur run --agent --since origin/main
      ```

      Read the JSON on stdout. `status` is `complete`, `partial` or `not_applicable`.
      The exit code is strict: 0 means complete and clean, 1 means a survivor needs
      review, 2 means a bad command or config, 3 means the run was incomplete or failed.

      When a mutant survives:

      1. Pick one live survivor from `findings.shown`.
      2. Add the smallest test that checks the observable behavior the mutant changed.
      3. Replay it with the command in `next.replay` (it uses the recorded seed) and
         confirm the mutant is now killed.
      4. Run the diff again. Repeat until the exit code is 0.

      Rules:

      - Report `partial` and `not_applicable` results as they are. Say what had no
        coverage or was capped; do not call an incomplete run clean.
      - Never change production behavior only to kill a mutant.
      - Never add survivors to the ignore list yourself. Ask the owner.
      - Run `saboteur help` for every command, option and exit code.
    MARKDOWN
  end
end
