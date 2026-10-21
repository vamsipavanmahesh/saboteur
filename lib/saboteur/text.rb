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

    # "1 subject" / "2 subjects": the count with the noun in the right
    # number (review C9). An irregular plural passes explicitly.
    def counted(count, singular, plural = "#{singular}s")
      "#{count} #{count == 1 ? singular : plural}"
    end

    # A list for a warning or note: the first five items, then "and N more".
    # One rule for every message that names files, subjects or specs (#332).
    # Items are repo-controlled text, so each is display_safe (#834).
    def name_list(items, limit: 5)
      shown = items.first(limit).map { |item| display_safe(item.to_s) }.join(", ")
      rest = items.size - limit
      rest.positive? ? "#{shown} and #{rest} more" : shown
    end

    # Display-safe single line for text a repository controls (file names,
    # config patterns, subject ids) before it joins a warning CI prints
    # (#834): control characters become \xNN escapes so an injected newline
    # cannot start a fresh line, a "##[" anywhere (Azure DevOps) loses its
    # bracket, and a "::" starting the text (a GitHub workflow command -
    # the runner trims leading whitespace first) loses its first colon.
    # Other colons and brackets, as in "Saboteur::Error", stay as they are.
    # Invalid UTF-8 is scrubbed first, as everywhere Text renders outside bytes.
    def display_safe(text)
      escaped = utf8(text).gsub(/[\x00-\x1f\x7f\u0080-\u009f]/) { |char| format("\\x%02x", char.ord) }
      escaped.gsub("##[", "##\\x5b").sub(/\A[[:space:]]*\K:(?=:)/) { "\\x3a" }
    end

    # display_safe for a message that is meant to span lines (an action line,
    # then indented detail lines). Each line is made safe on its own, so a
    # line of repository text that starts "::error::" after an injected
    # newline loses its colon, while the message's own line breaks stay.
    # Idempotent: escaping an already escaped message changes nothing.
    def display_safe_lines(text)
      utf8(text).lines.map { |line| display_safe(line.delete_suffix("\n")) + (line.end_with?("\n") ? "\n" : "") }.join
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
      string.dup.force_encoding(Encoding::UTF_8)
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
