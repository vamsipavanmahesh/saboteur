# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module Saboteur
  class Engine
    # Says why the coverage cache missed (#46). The map is keyed on the
    # content of every source, spec and support file, so a pull request that
    # edits one never hits a map built on the base branch; without a note the
    # run just sits through a whole-suite pass. The note names how many input
    # files changed since the last map, and points at the spec scoping flags.
    #
    # The comparison needs the earlier map's inputs: see
    # CoverageInputsSnapshot, which validates what is read back from the
    # cache (diagnostic only, never the authority for reusing a map). Every
    # path shown goes through the caller's line cleaner, since a file name, or
    # a key in a restored snapshot, is untrusted text that a CI log would
    # otherwise read as a workflow command.
    class CoverageMissNote
      NAMED = 3
      HINT = "; --test narrows the specs the build runs"

      # settings: whatever else is part of the cache key (config inputs, version).
      # map_key: the key the map about to be built is saved under.
      # seed: the seed that build runs the specs with.
      # clean: turns one path into a line-safe string.
      def initialize(cache_dir:, root:, files:, settings:, map_key:, seed:, clean:)
        @cache_dir = cache_dir
        @root = root
        @clean = clean
        @current = CoverageInputsSnapshot.build(root: root, files: files, settings: settings, map_key: map_key,
                                                seed: seed)
      end

      # The inputs snapshot of the run about to build its map.
      attr_reader :current

      def message(scoped:)
        head = "coverage cache miss: #{reason}; the map build runs "
        scoped ? "#{head}the selected specs once" : "#{head}the whole suite once#{HINT}"
      end

      # Call after the map is saved: the snapshot is written last and names it.
      def save
        CoverageInputsSnapshot.write(@cache_dir, @current)
      end

      private

      def reason
        earlier = CoverageInputsSnapshot.latest(@cache_dir, @root)
        return "no earlier map to compare with" unless earlier

        now = @current["files"]
        before = earlier["files"]
        parts = []
        parts << files_note(now, before) unless now == before
        parts << "settings, Ruby or saboteur version changed" if settings_changed?(earlier)
        parts.empty? ? "inputs match the last snapshot but its map file is missing or unusable" : parts.join("; ")
      end

      # "2 edited, 1 added, 1 removed", then the first few paths. Edited:
      # present on both sides with another digest.
      def files_note(now, before)
        edited = (now.keys & before.keys).reject { |name| now[name] == before[name] }
        added = now.keys - before.keys
        removed = before.keys - now.keys
        counts = { "edited" => edited, "added" => added, "removed" => removed }
                 .reject { |_, names| names.empty? }.map { |word, names| "#{names.size} #{word}" }
        "input files changed since the last map: #{counts.join(', ')} (#{named(edited + added + removed)})"
      end

      def named(names)
        shown = names.sort.first(NAMED).map { |name| @clean.call(name) }.join(", ")
        names.size > NAMED ? "#{shown}, +#{names.size - NAMED} more" : shown
      end

      def settings_changed?(earlier)
        earlier["settings"] != @current["settings"] || earlier["runtime"] != @current["runtime"]
      end
    end
  end
end
