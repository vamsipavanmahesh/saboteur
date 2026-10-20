# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"

module Saboteur
  class Engine
    # CoverageStore's saved parts (#427): the map of each finished part of a
    # parallel build is kept beside the whole-map cache, so a rerun after a
    # failed or budget-stopped build only rebuilds the parts that did not
    # finish. Uses the store's @config and cache_key.
    module CoverageParts
      private

      # One finished part's map, beside the cache of the whole map and under
      # the same key, so it is valid for exactly the inputs that cache is.
      def part_path(files, index, count)
        File.join(@config.path("cache_dir"), "coverage-#{cache_key(files)}-part-#{index + 1}-of-#{count}.json")
      end

      # Best effort, like the verdict checkpoint: a full disk or a read-only
      # cache dir must not hide the failure this build is about to report.
      # The saved maps of earlier runs' finished parts that still hold exactly
      # their part's examples; nil for a part that has to be built.
      def saved_parts(files, count, counts)
        Array.new(count) do |index|
          next unless @config["cache"]

          map = Selection::CoverageMap.load(part_path(files, index, count))
          map if map && map.tests.size == counts[index]
        end
      end

      # The saved parts are spent once the whole map exists.
      def forget_parts(files, count)
        count.times do |index|
          FileUtils.rm_f(part_path(files, index, count))
        rescue SystemCallError
          nil
        end
      end

      def save_part(map, files, index, count)
        map.save(part_path(files, index, count)) if @config["cache"] && !map.tests.empty?
      rescue SystemCallError
        nil
      end
    end
  end
end
