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
    # The comparison needs the earlier map's inputs, so each saved map leaves
    # a small snapshot (relative path => content digest) in the cache dir.
    #
    # The snapshot is diagnostic only. It is read from a restorable cache, so
    # it is validated no further than "a JSON object with a files hash"; it
    # must never be the authority for deciding that part of a map can be
    # reused. Every path shown goes through the caller's line cleaner, since a
    # file name, or a key in a restored snapshot, is untrusted text that a CI
    # log would otherwise read as a workflow command.
    class CoverageMissNote
      SNAPSHOT = "inputs-coverage.json"
      NAMED = 3
      HINT = "; --test narrows the specs the build runs"

      # settings: whatever else is part of the cache key (config inputs, version).
      # clean: turns one path into a line-safe string.
      def initialize(cache_dir:, root:, files:, settings:, clean:)
        @path = File.join(cache_dir, SNAPSHOT)
        @clean = clean
        @current = { "settings" => Digest::SHA256.hexdigest(settings.to_s),
                     "files" => files.to_h { |file| [relative(root, file), digest(file)] } }
      end

      def message(scoped:)
        head = "coverage cache miss: #{reason}; the map build runs "
        scoped ? "#{head}the selected specs once" : "#{head}the whole suite once#{HINT}"
      end

      # Best effort: a diagnostics file that cannot be written must not stop
      # a run whose map is already built. Written through a temp file and
      # renamed, so a reader never sees half a snapshot.
      def save
        FileUtils.mkdir_p(File.dirname(@path))
        temp = "#{@path}.#{Process.pid}.tmp"
        File.write(temp, JSON.generate(@current))
        File.rename(temp, @path)
      rescue SystemCallError, EncodingError, JSON::JSONError
        FileUtils.rm_f(temp) if temp
      end

      private

      def reason
        earlier = load
        return "no earlier map to compare with" unless earlier

        now = @current["files"]
        before = earlier["files"]
        parts = []
        parts << files_note(now, before) unless now == before
        parts << "settings or saboteur version changed" if earlier["settings"] != @current["settings"]
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

      def load
        data = JSON.parse(File.read(@path))
        data if data.is_a?(Hash) && data["files"].is_a?(Hash)
      rescue SystemCallError, JSON::ParserError
        nil
      end

      def relative(root, file)
        file.delete_prefix("#{root}/")
      end

      def digest(file)
        File.file?(file) && Digest::SHA256.file(file).hexdigest
      end
    end
  end
end
