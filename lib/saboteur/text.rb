# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # Bytes arriving from outside the process (git output, cache and log files,
  # worker pipes) are tagged with the process locale. Under a non-UTF-8
  # locale such as LANG=C that tag is US-ASCII, where any non-ASCII byte
  # raises on use. Re-tag everything crossing the boundary as UTF-8,
  # replacing bytes that are not valid UTF-8.
  module Text
    module_function

    def utf8(string)
      string.dup.force_encoding(Encoding::UTF_8).scrub
    end
  end
end
