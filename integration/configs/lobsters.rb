# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# UNVERIFIED LOCALLY: written without a Ruby 4.0 toolchain; the first CI run
# is the check. lobsters runs on sqlite; its test databases live under db/test.
Saboteur.configure do |c|
  c.include = %w[
    app/models/story.rb
    app/models/comment.rb
    app/models/user.rb
  ]
  c.tests = %w[spec/models]
  c.jobs = 1
  c.baseline_passes = 1
  c.coverage_recorder = ENV.fetch("SABOTEUR_COVERAGE_RECORDER", "coverage")
  c.sandbox_writable = %w[db/test tmp log]
end
