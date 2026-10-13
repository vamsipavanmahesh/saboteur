# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # Wraps text in ANSI colour codes when colour is on, and returns it
    # unchanged when it is off. Colour is on only when asked for or when the
    # output is a terminal and NO_COLOR is not set (https://no-color.org).
    class Palette
      CODES = { red: 31, green: 32, yellow: 33, magenta: 35, cyan: 36, dim: 2, bold: 1 }.freeze

      # mode: :auto, :always or :never.
      def self.for(out, mode: :auto, environment: ENV)
        enabled = case mode
                  when :always then true
                  when :never then false
                  else out.respond_to?(:tty?) && out.tty? && environment["NO_COLOR"].to_s.empty?
                  end
        new(enabled: enabled)
      end

      def initialize(enabled:)
        @enabled = enabled
      end

      def enabled?
        @enabled
      end

      def paint(color, text)
        return text unless @enabled

        "\e[#{CODES.fetch(color)}m#{text}\e[0m"
      end
    end
  end
end
