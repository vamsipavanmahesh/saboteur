# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"

module Saboteur
  class Engine
    # Identity file for a --resume directory (#471). The verdicts live in
    # ResultCache; this only records what the run was computed from, so a
    # later run with other inputs fails loudly instead of reusing the
    # directory under a different meaning.
    #
    # The file is untrusted input: it is read only when it is a regular
    # file (never a FIFO or a symlink), under a size cap, and must hold
    # exactly the three expected keys with bounded String values.
    class ResumeManifest
      FORMAT = 1
      FILE = "manifest.json"
      KEYS = %w[format identity version].freeze
      MAX_BYTES = 4096
      MAX_FIELD = 512

      # Raised when the directory belongs to another run or cannot be read.
      class Mismatch < StandardError; end

      # identity: a String that changes whenever the run's inputs change
      # (the RunFingerprint digest joined with the settings that pick the
      # mutants), at most MAX_FIELD characters.
      def initialize(directory:, identity:)
        @directory = directory
        @identity = identity
      end

      def path
        File.join(@directory, FILE)
      end

      # Creates the manifest in a fresh directory, accepts a matching one,
      # and raises Mismatch for anything else.
      def verify!
        File.lstat(path)
        compare(read)
      rescue Errno::ENOENT
        write
      end

      private

      def compare(stored)
        return if stored["identity"] == @identity && stored["version"] == VERSION

        raise Mismatch, "#{path}: the run inputs changed since this directory was created; " \
                        "delete it or choose a new --resume path"
      end

      def read
        raise Mismatch, "#{path}: unreadable manifest" unless File.lstat(path).file?

        validate(parse(slurp))
      rescue SystemCallError
        raise Mismatch, "#{path}: unreadable manifest"
      end

      def slurp
        File.open(path, File::RDONLY | File::NONBLOCK | File::NOFOLLOW) do |io|
          text = io.read(MAX_BYTES) || +""
          raise Mismatch, "#{path}: manifest too large" unless io.eof?

          text
        end
      end

      def parse(text)
        raise Mismatch, "#{path}: unreadable manifest" unless text.force_encoding(Encoding::UTF_8).valid_encoding?

        JSON.parse(text)
      rescue JSON::ParserError
        raise Mismatch, "#{path}: unreadable manifest"
      end

      def validate(data)
        raise Mismatch, "#{path}: unsupported manifest format" unless
          data.is_a?(Hash) && data.keys.sort == KEYS && data["format"] == FORMAT && bounded?(data)

        data
      end

      def bounded?(data)
        %w[identity version].all? { |key| data[key].is_a?(String) && data[key].length <= MAX_FIELD }
      end

      # Written to a private temp file and linked into place: link fails
      # when another run created the manifest first, and then that run's
      # manifest is the one compared.
      def write
        FileUtils.mkdir_p(@directory)
        temp = "#{path}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp"
        File.write(temp, JSON.generate(format: FORMAT, version: VERSION, identity: @identity))
        File.link(temp, path)
        nil
      rescue Errno::EEXIST
        compare(read)
      ensure
        FileUtils.rm_f(temp) if temp
      end
    end
  end
end
