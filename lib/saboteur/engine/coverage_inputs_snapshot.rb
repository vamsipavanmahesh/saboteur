# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require_relative "../text"

module Saboteur
  class Engine
    # The inputs a coverage map was built from, saved beside it as
    # inputs-<map key>.json: relative path => content digest, plus the
    # settings digest, the runtime identity (RunFingerprint.runtime_identity
    # and the map format) and the project root.
    #
    # Diagnostic only (#46). A restored cache is untrusted data, so a
    # snapshot is accepted only when everything checks: size and entry caps,
    # an exact key set, every field's type and shape, the map key in the file
    # name, the project root, and the map file next to it with the digest
    # recorded when the pair was written. Anything else reads as no snapshot.
    # It still must not be the authority for reusing part of a map: it
    # describes the inputs, not what a test read from them.
    #
    # The pair is written map first, snapshot last, through a temp file and a
    # rename, so a snapshot never names a map that is not on disk.
    module CoverageInputsSnapshot
      FORMAT = 1
      PREFIX = "inputs-"
      MAX_BYTES = 8 * 1024 * 1024
      MAX_FILES = 100_000
      MAX_PATH = 4096
      MAX_CANDIDATES = 20
      HEX = /\A[0-9a-f]{64}\z/
      KEYS = %w[files format map_digest map_key root runtime settings].freeze

      module_function

      def path(cache_dir, map_key)
        File.join(cache_dir, "#{PREFIX}#{map_key}.json")
      end

      def map_path(cache_dir, map_key)
        File.join(cache_dir, "coverage-#{map_key}.json")
      end

      # The snapshot of the inputs now; map_digest is filled in by #write.
      def build(root:, files:, settings:, map_key:)
        { "format" => FORMAT, "map_key" => map_key, "map_digest" => nil, "root" => digest_of(root),
          "runtime" => runtime_digest, "settings" => digest_of(settings.to_s),
          "files" => files.to_h { |file| [relative(root, file), file_digest(file)] } }
      end

      def runtime_digest
        digest_of(JSON.generate(RunFingerprint.runtime_identity.merge(map_format: Selection::CoverageMap::FORMAT)))
      end

      # Best effort: a failed write leaves no snapshot and never stops a run.
      # The temp file is removed however the write ends, an interrupt included.
      def write(cache_dir, data)
        target = path(cache_dir, data["map_key"])
        map_digest = file_digest(map_path(cache_dir, data["map_key"]))
        return unless map_digest

        temp = "#{target}.#{Process.pid}.tmp"
        begin
          File.write(temp, JSON.generate(data.merge("map_digest" => map_digest)))
          File.rename(temp, target)
        ensure
          FileUtils.rm_f(temp)
        end
      rescue SystemCallError, EncodingError, JSON::JSONError
        nil
      end

      # The newest snapshot that passes every check, or nil.
      def latest(cache_dir, root)
        candidates = Dir.glob(File.join(cache_dir, "#{PREFIX}*.json")).sort_by { |file| -mtime(file) }
        candidates.first(MAX_CANDIDATES).each do |file|
          data = read(file, cache_dir, root)
          return data if data
        end
        nil
      end

      # Only a regular file is read, never a symlink, FIFO or device (their
      # File.size is 0 and a read would not end), and never more than the cap.
      def read(file, cache_dir, root)
        return nil unless File.lstat(file).file?

        text = File.open(file, File::RDONLY | File::NONBLOCK | File::NOFOLLOW) { |io| io.read(MAX_BYTES + 1) }
        return nil if text.nil? || text.bytesize > MAX_BYTES

        data = JSON.parse(Text.utf8_strict(text))
        data if valid?(data, file, cache_dir, root)
      rescue SystemCallError, JSON::ParserError, EncodingError
        nil
      end

      def valid?(data, file, cache_dir, root)
        return false unless data.is_a?(Hash) && data.keys.sort == KEYS && data["format"] == FORMAT
        return false unless %w[runtime settings map_digest].all? { |key| hex?(data[key]) }
        return false unless data["root"] == digest_of(root)
        # The key becomes a path only after this: a name with a separator can never equal a basename.
        return false unless File.basename(file) == "#{PREFIX}#{data['map_key']}.json"

        files_valid?(data["files"]) && file_digest(map_path(cache_dir, data["map_key"])) == data["map_digest"]
      end

      def files_valid?(files)
        files.is_a?(Hash) && files.size <= MAX_FILES && files.all? do |name, digest|
          name.valid_encoding? && name.bytesize <= MAX_PATH && (digest == false || hex?(digest))
        end
      end

      def hex?(value)
        value.is_a?(String) && value.match?(HEX)
      end

      def mtime(file)
        File.mtime(file).to_f
      rescue SystemCallError
        0.0
      end

      def relative(root, file)
        file.delete_prefix("#{root}/")
      end

      def file_digest(file)
        File.file?(file) && Digest::SHA256.file(file).hexdigest
      rescue SystemCallError
        false
      end

      def digest_of(text)
        Digest::SHA256.hexdigest(text)
      end
    end
  end
end
