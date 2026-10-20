# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  class Engine
    # The specs that read a constant a source file defines: the cold-start
    # choice for a file with no spec by name. The same lexical matching #538
    # uses for changed specs. A file no spec reads, or one read by more than
    # CAP specs (a hub: the choice is not selective), gets no entry.
    class ReferenceSpecs
      CAP = 10

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
        @constants.call(file).flat_map { |constant| ConstantReads.across(absolute_specs, constant).keys }
                  .uniq.sort.map { |path| path.delete_prefix("#{@root}/") }
      end
    end
  end
end
