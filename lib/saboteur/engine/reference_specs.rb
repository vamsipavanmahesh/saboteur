# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # The specs that read a constant a source file defines, or require it: the
    # cold-start choice for a file with no spec by name. The constant match is
    # the lexical matching #538 uses for changed specs; the require match
    # covers a file that defines only top-level methods. A file no spec reads or requires, or one read by more than
    # CAP specs (a hub: the choice is not selective), gets no entry.
    class ReferenceSpecs
      CAP = 10
      REQUIRE = /^\s*(require_relative|require)[ (]\s*["']([^"']+)["']/

      # constants: file => the constants it defines, as TestGuess shapes them
      # for ConstantReads.
      def initialize(root, constants)
        @root = root
        @constants = constants
      end

      # files: root-relative source files; spec_paths: root-relative spec
      # files of the suite. Returns file => sorted root-relative spec paths.
      def call(files, spec_paths)
        absolute = spec_paths.map { |path| File.join(@root, path) }
        absolute.select! { |path| File.file?(path) && !File.symlink?(path) }
        files.to_h { |file| [file, readers_of(file, absolute)] }
             .select { |_, readers| readers.any? && readers.size <= CAP }
      end

      private

      def readers_of(file, absolute_specs)
        read = @constants.call(file).flat_map { |constant| ConstantReads.across(absolute_specs, constant).keys }
        (read + requirers_of(file, absolute_specs)).uniq.sort.map { |path| path.delete_prefix("#{@root}/") }
      end

      # Specs that require the file: by path from the spec (require_relative)
      # or by load path from the file's source root (require "a/b" for
      # lib/a/b.rb). A bare basename is not a load path, so it matches nothing.
      def requirers_of(file, absolute_specs)
        stem = File.join(@root, file).delete_suffix(".rb")
        loadable = file.delete_suffix(".rb").sub(%r{\A[^/]+/}, "")
        absolute_specs.select { |spec| requires?(spec, stem, loadable) }
      end

      def requires?(spec, stem, loadable)
        File.read(spec, encoding: "UTF-8").scrub.scan(REQUIRE).any? do |kind, target|
          target = target.delete_suffix(".rb")
          kind == "require_relative" ? File.expand_path(target, File.dirname(spec)) == stem : target == loadable
        end
      rescue SystemCallError
        false
      end
    end
  end
end
