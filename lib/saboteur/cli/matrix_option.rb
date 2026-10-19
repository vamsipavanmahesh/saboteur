# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # The --matrix flag for `saboteur run` (#334).
    module MatrixOption
      private

      def define_matrix_option(opts)
        opts.on("--matrix", "Run every covering test per mutant and list blind and redundant tests") do
          set(:matrix, true)
        end
      end
    end
  end
end
