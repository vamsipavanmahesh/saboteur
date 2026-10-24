# saboteur configuration for a Rails + RSpec app. CLI flags override this file.
# Only the decisions a first run needs are set here; every other key keeps
# its default. Who changes what, key by key:
# https://github.com/vamsipavanmahesh/saboteur/blob/main/docs/config-keys.md
Saboteur.configure do |c|
  # First-run decision: what to mutate.
  c.include = ["app/**/*.rb"]
  # Empty base classes: nothing useful to mutate.
  c.exclude = [
    "app/models/application_record.rb",
    "app/controllers/application_controller.rb",
    "app/jobs/application_job.rb",
    "app/mailers/application_mailer.rb",
  ]
  c.require = ["./config/environment"] # boots the app before specs load
  c.rails = true                       # reconnect ActiveRecord after fork, per-worker databases
  # First-run decision: parallelism; use 1 if your specs share external state.
  c.jobs = 1 # field-run control: serial on 2 CPU/1.9GB box (user rule 2026-10-24; CLI --jobs N overrides for the parallel stage)
  # EX-1 (user-approved exclusion 2026-10-24 06:52 IST, field run only, no app file edits):
  # spec/features/user_administration_spec.rb ("banning" red on lobsters main @40753644, independent of
  # saboteur, untouched by any selected PR; likely related to lobsters issue #2263 - "likely", not proven).
  c.rspec_args = ["--exclude-pattern", "spec/features/user_administration_spec.rb"]
end
