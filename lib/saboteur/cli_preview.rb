# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module CLIPreview
    private

    def preview
      raise CLI::UsageError, "--dry-run and --list-operators print text, not --agent JSON" if agent?
      raise CLI::UsageError, "--id replays one mutant: not with --dry-run or --list-operators" if options[:id]

      return MutationSource::OperatorRegistry.list(@out) || CLI::EXIT_OK if options[:list_operators]

      Preview.new(config, out: @out, err: @err).call
      CLI::EXIT_OK
    end

    def define_output_options(opts)
      opts.on("--json PATH", "Stryker JSON report path") { |v| set(:json_report, v) }
      opts.on("--html PATH", "Self-contained HTML report path") { |v| set(:html_report, v) }
      opts.on("--format FORMAT", %w[text agent], "text (default) or agent: one bounded JSON summary on stdout, " \
                                                 "strict exit codes") { |v| @format = v }
      opts.on("--agent", "Same as --format agent") { @format = "agent" }
    end
  end
end
