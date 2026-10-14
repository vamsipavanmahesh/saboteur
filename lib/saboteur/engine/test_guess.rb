# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # --guess-tests: the specs that sit next to the changed source files by
    # naming convention (lib/a/b.rb -> spec/a/b_spec.rb). A guess, not a
    # coverage fact: a spec that only reaches the file through another one
    # is not found. The run scopes to the guesses only when every changed
    # file has one.
    class TestGuess
      Result = Data.define(:specs, :unmatched, :changed)

      SOURCE_ROOTS = %w[lib app].freeze

      def initialize(config)
        @root = File.realpath(config.root)
        @config = config
      end

      # specs: existing spec files (relative paths); unmatched: changed
      # source files with no guessed spec; changed: how many source files
      # changed.
      def call
        changed = changed_sources
        guesses = changed.to_h { |file| [file, guess_for(file)] }
        Result.new(specs: guesses.values.compact.uniq.sort, unmatched: guesses.select { |_, spec| spec.nil? }.keys,
                   changed: changed.size)
      end

      private

      # Changed files that saboteur would mutate, relative to the root.
      def changed_sources
        included = @config.included_files.to_set
        changed = Selection::GitDiff.changed_lines(@config["since"], root: @root).keys
        changed.map { |file| Selection::CoverageMap.canonical(file) }
               .select { |file| included.include?(file) }
               .map { |file| file.delete_prefix("#{@root}/") }.sort
      end

      def guess_for(file)
        stem = file.delete_suffix(".rb")
        rest = stem.split("/", 2)
        candidates = ["spec/#{stem}_spec.rb"]
        candidates.unshift("spec/#{rest.last}_spec.rb", "spec/lib/#{rest.last}_spec.rb") if
          rest.size == 2 && SOURCE_ROOTS.include?(rest.first)
        candidates.find { |path| File.file?(File.join(@root, path)) }
      end
    end
  end
end
