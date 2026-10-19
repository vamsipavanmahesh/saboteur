# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"

module Saboteur
  # Bytes arriving from outside the process (git output, cache and log files,
  # worker pipes) are tagged with the process locale. Under a non-UTF-8
  # locale such as LANG=C that tag is US-ASCII, where any non-ASCII byte
  # raises on use. Re-tag everything crossing the boundary as UTF-8.
  module Text
    module_function

    # A list for a warning or note: the first five items, then "and N more".
    # One rule for every message that names files, subjects or specs (#332).
    def name_list(items, limit: 5)
      shown = items.first(limit).join(", ")
      rest = items.size - limit
      rest.positive? ? "#{shown} and #{rest} more" : shown
    end

    # Lossy: bytes that are not valid UTF-8 become the replacement
    # character. For log and message display only - never feed the result
    # back into filesystem, cache or protocol identity: scrubbing rewrites
    # raw bytes, which can alias two different names or make a path vanish
    # from a File.exist? probe.
    def utf8(string)
      string.dup.force_encoding(Encoding::UTF_8).scrub
    end

    # Lossless: every byte survives; only the encoding tag changes. Use for
    # paths and identity-bearing fields. File.* calls and String == then
    # work on the exact bytes git reported; only rendering (regexes over
    # arbitrary content, JSON, terminal output) needs #utf8.
    def utf8_identity(string)
      string.dup.force_encoding("UTF-8")
    end

    # Lossless + strict: retag without scrubbing, then reject bytes
    # that are not valid UTF-8 with JSON::ParserError, so a JSON
    # boundary's existing parse-error handling rejects corrupt input
    # instead of silently accepting a rewritten version of it.
    def utf8_strict(string)
      tagged = utf8_identity(string)
      raise JSON::ParserError, "invalid UTF-8" unless tagged.valid_encoding?

      tagged
    end
  end
end
