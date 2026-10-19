# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # `run --dry-run` and `run --list-operators`: plan output, no mutations
    # (#334). Extracted from CLI by command.
    module PreviewCommand
      private

      def preview
        raise UsageError, "--dry-run and --list-operators print text, not --agent JSON; use --format json" if agent?
        raise UsageError, "--id replays one mutant: not with --dry-run or --list-operators" if options[:id]

        if options[:list_operators]
          MutationSource::OperatorRegistry.list(@out, names: config["operators"],
                                                      excluded: config["exclude_operators"])
          return EXIT_OK
        end

        Preview.new(config, out: @out, err: @err, format: @format).call
        EXIT_OK
      end
    end
  end
end
