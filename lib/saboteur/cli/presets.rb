# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # Opinionated bundles (#244): pr is the fast changed-lines loop (one
    # baseline check, a 10-minute budget that does not fail the build),
    # audit is the whole project with both reports. Preset flags go first,
    # so an explicit flag after them wins on the usual last-flag rule.
    module Presets
      PRESETS = {
        "pr" => %w[--baseline-passes 1 --max-duration 10m --max-duration-ok],
        "audit" => %w[--all --operators all --baseline-passes 2 --json .saboteur/audit-report.json
                      --html .saboteur/audit-report.html]
      }.freeze

      private

      def preset(name)
        flags = PRESETS.fetch(name).dup
        if name == "pr"
          ref = @argv.first.nil? || @argv.first.start_with?("-") ? "main" : @argv.shift
          flags += ["--since", ref]
        end
        # Named tests are an explicit scope: the injected whole-suite --all
        # would reject the run, so it stays out (#245).
        flags.delete("--all") if @argv.any? { |arg| arg == "--test" || arg.start_with?("--test=") }
        @err.puts("saboteur: preset '#{name}': #{flags.join(' ')} (explicit flags override)")
        @argv = flags + @argv
        run_command
      end
    end
  end
end
