# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "digest"
require "json"

module Preflight
  # A Hash that refuses a repeated key, so a document cannot say two things at once.
  class UniqueKeyHash < Hash
    def []=(key, value)
      raise MalformedDocument, "duplicate key #{key.inspect}" if key?(key)

      super
    end
  end

  # JSON parsing for evidence: bounded size, no duplicate keys, no extensions.
  module StrictJson
    MAX_BYTES = 50 * 1024 * 1024

    module_function

    def parse(text)
      raise MalformedDocument, "document over #{MAX_BYTES} bytes" if text.bytesize > MAX_BYTES

      valid = text.dup.force_encoding(Encoding::UTF_8).valid_encoding?
      raise MalformedDocument, "document is not valid UTF-8" unless valid

      JSON.parse(text, object_class: UniqueKeyHash, max_nesting: 32)
    rescue JSON::ParserError => e
      raise MalformedDocument, "not valid JSON: #{e.message[0, 80]}"
    end

    # The one way evidence files are read: open once without blocking, then require the opened descriptor
    # to be a regular file. A FIFO or device swapped in after any earlier metadata check cannot hang the run.
    def open_regular(path, follow: true)
      flags = File::RDONLY | File::NONBLOCK | (follow ? 0 : File::NOFOLLOW)
      File.open(path, flags) do |file|
        raise MalformedDocument, "#{path} is not a regular file" unless file.stat.file?

        yield file
      end
    rescue SystemCallError, IOError => e
      raise MalformedDocument, "#{path} cannot be read: #{e.class}"
    end

    # Reads at most the limit plus one byte, so a growing or replaced file cannot exceed the cap.
    def read(path, follow: true)
      open_regular(path, follow: follow) do |file|
        bytes = file.read(MAX_BYTES + 1) || ""
        raise MalformedDocument, "#{path} is over #{MAX_BYTES} bytes" if bytes.bytesize > MAX_BYTES

        parse(bytes)
      end
    end

    # SHA-256 of a regular file through the same primitive, read in bounded chunks up to the cap.
    def digest(path, max_bytes: MAX_BYTES)
      open_regular(path) do |file|
        sha = Digest::SHA256.new
        total = 0
        while (chunk = file.read(1_048_576))
          total += chunk.bytesize
          raise MalformedDocument, "#{path} is over #{max_bytes} bytes" if total > max_bytes

          sha << chunk
        end
        sha.hexdigest
      end
    end

    def count?(value)
      value.is_a?(Integer) && !value.negative?
    end
  end
end
