# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # Where a run's own output goes: the report names it prints and the
    # stdout redirect that keeps agent JSON clean (#334). Extracted from CLI.
    module RunOutput
      private

      # One line naming the reports written, paths relative to the root when
      # they sit under it (a blank line before it, as the old JSON line had).
      def announce_reports(reports)
        return if (written = reports.select { |path, _label| path }).empty?

        root = File.join(File.realpath(config.root), "")
        names = written.map do |path, label|
          shown = File.expand_path(path).delete_prefix(root)
          "#{shown} (#{label})"
        end
        @out.puts "\nReports: #{names.join(', ')}"
      end

      # Agent mode: stdout carries exactly one JSON payload. The target's own output (boot
      # files, hooks, spec loading, child processes) goes to stderr while the engine runs.
      # Descriptor 1 points at stderr for the block, so Kernel#puts, system and forked
      # children cannot write into the JSON on stdout.
      def stdout_on_stderr
        saved = $stdout.dup
        $stdout.reopen($stderr)
        yield
      ensure
        $stdout.reopen(saved) if saved
        saved&.close
      end
    end
  end
end
