# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "prism"
require "shellwords"
require_relative "mutation_source/operator_registry"

module Saboteur
  # Only real Ruby comments can suppress edits, never text inside a string.
  class InlineSuppression
    Directive = Data.define(:line, :operators, :reason)

    def initialize(file, source)
      @file = file
      @directives = Prism.parse(source).comments.filter_map { |comment| parse(comment) }
    end

    def reason(subject, mutation)
      mutation.edits.each do |edit|
        line = subject.line_of(edit.start_byte)
        directive = @directives.find do |entry|
          entry.line == line && (entry.operators.empty? || entry.operators.include?(mutation.operator))
        end
        return directive if directive
      end
      nil
    end

    private

    def parse(comment)
      text = comment.location.slice.sub(/\A#\s*/, "")
      return nil unless text.start_with?("saboteur:disable-line")

      line = comment.location.start_line
      tokens = Shellwords.split(text)
      fail_at(line, "expected saboteur:disable-line") unless tokens.shift == "saboteur:disable-line"
      reasons, operators = tokens.partition { |token| token.start_with?("reason=") }
      reason, = reasons
      fail_at(line, "one nonblank reason=\"...\" is required") unless
        reasons.size == 1 && !reason.delete_prefix("reason=").strip.empty?
      validate_operators(operators, line)
      Directive.new(line: line, operators: operators, reason: reason.delete_prefix("reason="))
    rescue ArgumentError => e
      fail_at(line, "invalid suppression: #{e.message}")
    end

    def validate_operators(operators, line)
      unknown = operators - MutationSource::OperatorRegistry::DESCRIPTIONS.keys
      fail_at(line, "unknown operators: #{unknown.join(', ')}") unless unknown.empty?
    end

    def fail_at(line, message)
      raise ConfigError, "#{@file}:#{line}: #{message}"
    end
  end
end
