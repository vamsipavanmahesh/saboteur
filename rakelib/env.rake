# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# bin/check-env is the fail-fast environment gate (AGENTS.md, "Run
# discipline"). Every test and acceptance entry point depends on it, so a
# broken toolchain stops before the suite spends a minute.
desc "Fail fast when the environment cannot run the suite faithfully"
task :check_env do
  sh "ruby bin/check-env"
end

task spec: :check_env
