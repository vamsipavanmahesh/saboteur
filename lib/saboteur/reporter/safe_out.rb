# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "delegate"
require_relative "palette"

module Saboteur
  module Reporter
    # The terminal report's one way out. Test ids, file names, subject ids and
    # result locations come from the repository under test, so every line goes
    # through Text.display_safe before it is written: control characters are
    # escaped and a line cannot start a CI workflow command ("::error::",
    # "##[error]"). Our own colour codes and tabs, which the report writes on
    # purpose, are kept: only the exact sequences Palette writes, never a
    # generic one such as "\e[8m" (conceal), and no tabs.
    class SafeOut < SimpleDelegator
      SGR = /(\e\[(?:#{(Palette::CODES.values + [0]).join('|')})(?:;(?:#{(Palette::CODES.values + [0]).join('|')}))*m)/

      def puts(*lines)
        super(*lines.flatten.map { |line| safe(line.to_s) })
      end

      private

      def safe(text)
        text.split(SGR).each_with_index.map do |part, index|
          index.odd? ? part : Text.display_safe_lines(part)
        end.join
      end
    end
  end
end
