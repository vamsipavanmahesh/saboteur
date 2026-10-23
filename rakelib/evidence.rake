# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "English"

# `rake acceptance` runs the full suite, including the slow full-tier
# scenarios such as money_ranking.
desc "Run the full acceptance harness: every maintainer scenario, pass/fail each"
task acceptance: :check_env do
  ruby "acceptance/runner.rb"
end

namespace :acceptance do
  desc "Run the fast acceptance tier (every pull request)"
  task fast: :check_env do
    sh({ "ACCEPTANCE_TIER" => "fast" }, "ruby acceptance/runner.rb")
  end

  desc "Run the full acceptance tier (release gate; includes money_ranking)"
  task full: :check_env do
    ruby "acceptance/runner.rb"
  end
end

# The release gate. Each step runs even when an earlier step failed so the
# summary shows the full state; the task exits non-zero when any step failed.
# The environment gate runs first as a prerequisite and stops the task outright.
RELEASE_CHECK_STEPS = [
  ["unit suite", "bundle exec rspec --exclude-pattern 'spec/e2e/**/*_spec.rb'"],
  ["e2e suite", "bundle exec rspec spec/e2e"],
  ["acceptance harness (full)", "ruby acceptance/runner.rb"],
  ["claims check", "script/claims-check"]
].freeze

namespace :release do
  desc "Run the release gate: unit suite, e2e suite, acceptance harness, claims check"
  # check_env is a prerequisite, not a collected step: a red environment
  # aborts the gate before any suite step runs.
  task check: :check_env do
    results = []
    RELEASE_CHECK_STEPS.each do |name, command|
      puts "\n#{'=' * 60}\nrelease:check - #{name}\n#{'=' * 60}\n"
      start = Time.now
      ok = system(command)
      results << [name, ok ? 0 : $CHILD_STATUS.exitstatus || 1, (Time.now - start).round]
    end

    puts "\n#{'=' * 60}\nrelease:check summary\n#{'=' * 60}\n"
    failed = false
    results.each do |name, code, seconds|
      state = code.zero? ? "PASS" : "FAIL"
      failed ||= code.nonzero?
      puts format("%<name>-20s %<state>-4s %<seconds>ds", name:, state:, seconds:)
    end
    puts failed ? "\nrelease:check FAILED" : "\nrelease:check PASSED"
    exit 1 if failed
  end
end
