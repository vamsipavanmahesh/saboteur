# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # Refuses linked or non-regular history/report destinations before writes.
    module HistoryPaths
      module_function

      def validate(paths)
        paths = paths.compact.map { |path| File.expand_path(path) }
        identities = paths.map do |path|
          reject_links(path)
          next unless File.exist?(path)

          stat = File.stat(path)
          raise Error, "score history/report destination must be a regular file" unless stat.file?

          [stat.dev, stat.ino]
        end.compact
        raise Error, "score history/report destinations alias the same file" unless identities.uniq == identities
      rescue SystemCallError => e
        raise Error, "score history/report paths cannot be verified: #{e.message}"
      end

      def reject_links(path)
        loop do
          raise Error, "score history/report paths must not contain symlinks" if File.symlink?(path)

          parent = File.dirname(path)
          break if parent == path

          path = parent
        end
      end
    end
  end
end
