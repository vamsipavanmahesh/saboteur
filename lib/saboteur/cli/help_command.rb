# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # `saboteur help` and the `--help` of every command (#334). Extracted
    # from CLI by command.
    module HelpCommand
      private

      def help_command
        consume_color_options
        show_help(@argv.shift)
      end

      def help_requested? = @argv.intersect?(%w[--help -h])

      def show_help(command_name)
        help = Help.new(option_lines: option_lines)
        text = command_name ? help.command(command_name) : help.overview
        return @out.puts(text) || EXIT_OK if text

        @err.puts("unknown command: #{command_name}. Commands: #{help.command_names.join(', ')}")
        EXIT_USAGE
      end
    end
  end
end
