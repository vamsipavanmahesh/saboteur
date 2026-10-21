# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    # Wraps text in ANSI colour codes when colour is on, and returns it
    # unchanged when it is off. Six semantic tokens cover every painted
    # element; colour is never the sole carrier, so each coloured element
    # also has a word or glyph in the text.
    class Palette
      CODES = { red: 31, green: 32, yellow: 33, magenta: 35, cyan: 36, dim: 2, bold: 1 }.freeze
      TOKENS = { fail: %i[red bold], pass: %i[green], warn: %i[yellow], info: %i[cyan], dim: %i[dim],
                 head: %i[bold] }.freeze
      # Unicode glyphs and their ASCII fallback under TERM=dumb or a
      # non-UTF-8 locale: check -> v, cross -> x, arrow -> ->, middot -> *.
      GLYPHS = { check: ["✓", "v"], cross: ["✗", "x"], arrow: ["→", "->"], middot: ["·", "*"] }.freeze

      # mode: :auto, :always or :never. Precedence, highest first: the mode,
      # TERM=dumb, NO_COLOR (any non-empty value, per no-color.org),
      # FORCE_COLOR/CLICOLOR_FORCE, then auto: colour when the stream is a
      # terminal or a known colour-capable CI (GITHUB_ACTIONS).
      def self.for(out, mode: :auto, environment: ENV, overrides: nil)
        new(enabled: enabled?(out, mode, environment), ascii: ascii?(environment), overrides:)
      end

      def self.enabled?(out, mode, environment)
        case mode
        when :always then true
        when :never then false
        else
          return false if environment["TERM"] == "dumb"
          return false unless environment["NO_COLOR"].to_s.empty?
          return true if %w[FORCE_COLOR CLICOLOR_FORCE].any? { |name| !environment[name].to_s.empty? }

          (out.respond_to?(:tty?) && out.tty?) || environment.key?("GITHUB_ACTIONS")
        end
      end

      def self.ascii?(environment)
        return true if environment["TERM"] == "dumb"

        locale = environment["LC_ALL"] || environment["LC_CTYPE"] || environment["LANG"]
        !locale.nil? && !locale.match?(/UTF-?8/i)
      end

      # A c.palette override maps a token to an ANSI colour name (or names).
      def self.validate_overrides!(overrides)
        unknown = overrides.keys.map(&:to_sym) - TOKENS.keys
        unless unknown.empty?
          raise ArgumentError, "unknown palette tokens: #{unknown.join(', ')} (valid: #{TOKENS.keys.join(', ')})"
        end

        bad = overrides.values.flatten.map(&:to_sym) - CODES.keys
        return if bad.empty?

        raise ArgumentError, "unknown palette colours: #{bad.join(', ')} (valid: #{CODES.keys.join(', ')})"
      end

      def initialize(enabled:, ascii: false, overrides: nil)
        @enabled = enabled
        @ascii = ascii
        @tokens = TOKENS
        return if overrides.nil? || overrides.empty?

        self.class.validate_overrides!(overrides)
        @tokens = TOKENS.merge(overrides.to_h { |key, names| [key.to_sym, Array(names).map(&:to_sym)] })
      end

      def enabled?
        @enabled
      end

      # Call sites convert to contract tokens in follow-up slices; until
      # then a legacy colour name still paints its own code.
      def paint(token, text)
        return text unless @enabled

        names = @tokens.fetch(token) { [token] }
        "\e[#{names.map { |name| CODES.fetch(name) }.join(';')}m#{text}\e[0m"
      end

      def glyph(name)
        unicode, fallback = GLYPHS.fetch(name)
        @ascii ? fallback : unicode
      end
    end
  end
end
