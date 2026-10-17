# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Selection
    # Positional source-scope arguments from the command line.
    module SourceScope
      module_function

      # "One --test, several paths" lands the extra paths in the source
      # scope; specs are never subjects, so the run would mutate nothing
      # and still exit 0. Refuse them as a usage error before any boot.
      def verify_no_specs!(paths)
        spec_files = paths.select { |path| path.end_with?("_spec.rb") }
        return if spec_files.empty?

        raise ConfigError,
              "spec files are not mutated - pass them with --test, one path per use: #{spec_files.join(', ')}"
      end
    end
  end
end
