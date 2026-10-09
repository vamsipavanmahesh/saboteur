# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"
require "shellwords"

module Saboteur
  class Engine
    # The files every test shares: spec helpers and support code, boot and
    # hook files, .rspec and whatever it (or rspec_args) requires. A change
    # to any of them can change what any test runs, so both the coverage
    # map and the result cache depend on them. Example files (*_spec.rb)
    # are not listed: each is tracked with its own tests.
    class SuiteFiles
      OPTION_FILES = %w[.rspec .rspec-local].freeze
      REQUIRE_FLAGS = %w[--require -r].freeze
      LOAD_PATH = %w[spec lib .].freeze

      def initialize(config)
        @config = config
        @root = File.realpath(config.root)
      end

      def files
        (shared_spec_files + boot_and_hook_files + option_files + required_by_options).uniq.sort
      end

      def digest
        files.each_with_object(Digest::SHA256.new) do |file, sha|
          sha << file << "\0" << Digest::SHA256.file(file).hexdigest << "\0"
        end.hexdigest
      end

      private

      def shared_spec_files
        Dir.glob("spec/**/*.rb", base: @root).reject { |file| file.end_with?("_spec.rb") }
           .map { |file| File.join(@root, file) }
      end

      def boot_and_hook_files
        (@config["require"] + @config["hooks"]).filter_map { |file| existing(File.expand_path(file, @root)) }
      end

      def option_files
        OPTION_FILES.map { |file| File.join(@root, file) }.select { |file| File.file?(file) }
      end

      # `--require name` resolves through RSpec's load path (spec/, lib/).
      def required_by_options
        option_files.flat_map { |file| required_names(Shellwords.split(File.read(file))) }
                    .concat(required_names(@config["rspec_args"]))
                    .filter_map { |name| resolve(name) }
      end

      def required_names(tokens)
        tokens.each_with_index.filter_map do |token, index|
          flag, value = token.split("=", 2)
          next unless REQUIRE_FLAGS.include?(flag)

          value || tokens[index + 1]
        end
      end

      def resolve(name)
        LOAD_PATH.lazy.filter_map { |dir| existing(File.expand_path(name, File.join(@root, dir))) }.first
      end

      def existing(path)
        [path, "#{path}.rb"].find { |candidate| File.file?(candidate) }
      end
    end
  end
end
