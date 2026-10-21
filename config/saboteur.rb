# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# saboteur on its own code (CI runs it in diff mode: --since origin/main).
Saboteur.configure do |c|
  c.include = ["lib/**/*.rb"]
  # Default inference: files whose specs break the naming mirror are mapped
  # in config/saboteur_custom_map.rb instead of falling back to :all.

  # These run inside every mutant child (fork supervision, hooks, the test
  # adapters, the orchestration around them). Mutating them breaks the
  # harness that reports the result, which shows up as errors, not as
  # information about the tests.
  c.exclude = ["lib/saboteur/version.rb", "lib/saboteur/execution/**/*.rb", "lib/saboteur/hooks.rb",
               "lib/saboteur/integration/**/*.rb"]
  # Unit specs only. End-to-end specs run saboteur in subprocesses, so they
  # never cover lib/ code in this process; spec/fixtures holds target projects.
  c.rspec_args = ["spec/saboteur"]
end
