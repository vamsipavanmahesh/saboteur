# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module MutationSource
    # A replacement of source bytes [start_byte, end_byte) in file with text.
    # Offsets are byte offsets into the file as read from disk (UTF-8),
    # matching Prism::Location#start_offset / #end_offset.
    Edit = Data.define(:file, :start_byte, :end_byte, :replacement) do
      def initialize(file:, start_byte:, end_byte:, replacement:)
        raise ArgumentError, "start_byte must be >= 0" if start_byte.negative?
        raise ArgumentError, "end_byte must be >= start_byte" if end_byte < start_byte

        super
      end
    end
  end
end
