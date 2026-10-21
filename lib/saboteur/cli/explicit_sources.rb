# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class CLI
    # The source and test operands of `saboteur run`, checked against the
    # file system before anything boots (#334). Extracted from CLI.
    module ExplicitSources
      private

      # Positional arguments name the files (or directories) to mutate. They
      # replace the configured include and exclude patterns. Each must exist,
      # so a typo is an error and not a run over zero subjects.
      def use_explicit_sources
        Selection::SourceScope.verify_no_specs!(@argv)
        options[:tests]&.each { |test| require_existing_test(test) }
        # --test may stand alone: the configured include (or the --since
        # diff) names the sources. The files must still exist.
        return if @argv.empty?

        @sources = @argv.dup
        options[:include] = @argv.map { |source| source_pattern(source) }
        options[:exclude] = []
      end

      def source_pattern(source)
        return "#{glob_escape(source.chomp('/'))}/**/*.rb" if File.directory?(source)
        raise UsageError, "source is not a Ruby file: #{source}" if File.file?(source) && !source.end_with?(".rb")
        raise UsageError, "source file not found: #{source}" unless File.file?(source)

        glob_escape(source)
      end

      # include is a list of glob patterns; a named file must match only itself.
      def glob_escape(path)
        path.gsub(/[\\*?\[\]{}]/) { |character| "\\#{character}" }
      end

      # A test may carry an example selector: spec/a_spec.rb:12 or spec/a_spec.rb[1:2].
      def require_existing_test(test)
        path = test.sub(/(:\d+|\[[\d:,]+\])+\z/, "")
        raise UsageError, "test file not found: #{test}; check the path or drop --test" unless File.exist?(path)
      end
    end
  end
end
