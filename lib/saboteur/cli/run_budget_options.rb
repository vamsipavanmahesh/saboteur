# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # The run's clock and repeatability switches: seed, baseline check count
    # (#55) and the wall-clock budget (#245). Grouped so the option table in
    # the CLI stays under the house size caps.
    module RunBudgetOptions
      private

      def add_run_budget_options(opts)
        opts.on("--seed N", Integer, "Seed for Ruby's random numbers in every test run (default 1)") do |v|
          set(:seed, v)
        end
        opts.on("--coverage-parts N", Integer, "Build the coverage map in N parallel parts (default 1)") do |v|
          set(:coverage_parts, v)
        end
        opts.on("--baseline-passes N", Integer, "Unchanged-suite checks (default 2)") { |v| set(:baseline_passes, v) }
        opts.on("--max-duration DURATION", "Wall-clock budget for the whole run, e.g. 10m; exit 4 when spent - " \
                                           "the clock starts at engine entry, so boot, baselines and the " \
                                           "coverage map spend it too") do |v|
          set(:max_duration, parse_duration(v))
        end
        opts.on("--baseline PATH", "Gate the run on an accepted baseline: only new survivors or a score " \
                                   "drop beyond --epsilon fail (propose one with: saboteur baseline propose)") do |v|
          set(:baseline, v)
        end
        opts.on("--epsilon POINTS", Float, "With --baseline: allowed score drop in percentage points " \
                                           "(default 0: any drop fails)") { |v| set(:epsilon, v) }
        opts.on("--[no-]max-duration-ok", "An exhausted --max-duration budget does not fail the run") do |v|
          set(:max_duration_ok, v)
        end
      end

      # "10m" -> 600.0; bare numbers are seconds. A bad value is a usage error.
      def parse_duration(value)
        match = /\A(?<amount>\d+(?:\.\d+)?)(?<unit>[smh])?\z/.match(value.to_s.strip)
        unless match
          raise ConfigError,
                "invalid --max-duration #{value.inspect}: use seconds or an s/m/h suffix, e.g. 10m"
        end

        match[:amount].to_f * { "s" => 1, "m" => 60, "h" => 3600, nil => 1 }.fetch(match[:unit])
      end
    end
  end
end
