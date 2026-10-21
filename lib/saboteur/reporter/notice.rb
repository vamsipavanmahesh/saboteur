# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # One coat of paint for every warning notice: the fact lines carry the
    # :warn token, a "Fix:" line (the two-line shape) stays :dim. Colour
    # only - the writers own the wording, and monochrome passes the text
    # through byte-identical.
    module Notice
      module_function

      # Paint line by line so a multi-line notice keeps its shape: any line
      # starting with "Fix:" is the actionable tail and stays dim, every
      # other line is the warning fact.
      def paint(palette, text)
        text.lines.map do |line|
          line = line.chomp
          palette.paint(line.start_with?("Fix:") ? :dim : :warn, line)
        end.join("\n")
      end
    end
  end
end
