# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # The colour switches every command that prints text accepts (#1288).
    # --no-color stays as a deprecated alias for --color=never.
    module ColorOption
      private

      def define_color_options(opts)
        opts.on("--color [MODE]", %w[always never auto],
                "Colour the text report: always, never or auto (default: auto)") do |value|
          @color = (value || :always).to_sym
        end
        opts.on("--no-color", "Deprecated alias for --color=never") { @color = :never }
      end

      # Consume leading colour switches for commands that otherwise take
      # positional arguments only (help, explain).
      def consume_color_options
        OptionParser.new { |opts| define_color_options(opts) }.order!(@argv)
      end
    end
  end
end
