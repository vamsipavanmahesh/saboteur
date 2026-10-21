# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../starter_config"

module Saboteur
  class CLI
    # `saboteur init`: writes a working config/saboteur.rb for a plain
    # RSpec project and prints the next commands (#333). Never overwrites an
    # existing config unless --force.
    module InitCommand
      NEXT_COMMANDS = ["saboteur doctor", "saboteur run --since origin/main", "saboteur survivors"].freeze

      def init_parser
        OptionParser.new do |opts|
          opts.banner = "Usage: saboteur init [--force]"
          opts.on("--force", "Overwrite an existing config/saboteur.rb") { set(:force, true) }
        end
      end

      private

      def init_command = help_requested? ? show_help("init") : init

      def init
        init_parser.parse!(@argv)
        raise UsageError, "unexpected arguments: #{@argv.join(' ')}" if @argv.any?

        write_starter_config
      rescue ConfigError => e
        @err.puts("saboteur: #{Text.display_safe_lines(e.message)}")
        EXIT_USAGE
      end

      def write_starter_config
        relative = "config/saboteur.rb"
        path = File.join(Dir.pwd, relative)
        if (File.exist?(path) || File.symlink?(path)) && !options[:force]
          @err.puts("saboteur: #{relative} already exists (#{path}); pass --force to overwrite it")
          return EXIT_USAGE
        end
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, StarterConfig::TEXT)
        @out.puts("wrote #{relative}", "", "Next:")
        NEXT_COMMANDS.each { |command| @out.puts("  #{command}") }
        EXIT_OK
      end
    end
  end
end
