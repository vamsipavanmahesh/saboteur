# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "shellwords"

module Saboteur
  module Execution
    # Shape check for --test-command strings (#611). ruby executes only the
    # FIRST script named on its command line; extra .rb arguments become
    # ARGV, so "ruby -Itest a_test.rb b_test.rb" exercises a fraction of the
    # suite and the unrun files' mutants silently survive. Only that exact
    # shape warns: the command is split on shell operators (&&, ||, ;, |,
    # redirections excluded with their targets) and each simple command inspected on
    # its own; option operands (-r helper, -I dir, -C dir, -E/-F/-K values)
    # are parsed out and -e/--eval ends the search (the inline script
    # decides what it loads); the script must look like a test file, so a
    # custom runner taking file arguments stays quiet. Wrappers (env,
    # timeout, nice, time, bundle exec [--]) and versioned rubies
    # (ruby3.4) are unwrapped. Known false negatives, accepted: nested
    # shells (sh -c '...') and non-test file names.
    module TestCommandShape
      SHELL_OPERATOR_TOKENS = %w[&& || ; | &].freeze

      # ruby options that swallow the NEXT token as their operand, detached
      # form (-I lib); the attached form (-Ilib) is one token and needs no
      # skip.
      RUBY_OPERAND_OPTIONS = %w[-r -I -C -E -F -K --encoding --eval].freeze

      TEST_FILE = /\A(test_|spec_).*|(_test|_spec)\.rb\z/

      module_function

      def multi_file_ruby?(command)
        simple_commands(command).any? { |simple| ruby_multi_file_simple_command?(simple) }
      rescue ArgumentError
        false
      end

      # ";" is a shell separator whenever unquoted - even glued to the next
      # word ("cd spec;ruby ..."). Masking quoted and escaped semicolons
      # first keeps 'ruby "a;b_test.rb"' one script; other operators split
      # only as standalone tokens.
      def simple_commands(command)
        commands = [[]]
        semicolon_segments(command).each do |segment|
          Shellwords.split(segment).each do |token|
            if SHELL_OPERATOR_TOKENS.include?(token)
              commands << []
            else
              commands.last << token
            end
          end
          commands << []
        end
        commands.reject(&:empty?)
      end

      QUOTED_OR_ESCAPED = /"(?:\\.|[^"\\])*"|'[^']*'|\\./m

      def semicolon_segments(command)
        masked = command.gsub(QUOTED_OR_ESCAPED) { |span| span.tr(";", "\0") }
        masked.split(";", -1).map { |segment| segment.tr("\0", ";") }
      end

      def ruby_multi_file_simple_command?(tokens)
        tokens = unwrap(tokens)
        return false unless tokens.first&.then { |prog| File.basename(prog).match?(/\Aruby[\d.]*\z/) }

        args = tokens[1..]
        return false if args.any? { |token| token == "-e" || token.start_with?("-e") || token == "--eval" }

        script, *rest = script_operands(args)
        !script.nil? && script.end_with?(".rb") && File.basename(script).match?(TEST_FILE) &&
          rest.any? { |token| token.end_with?(".rb") }
      end

      def unwrap(tokens)
        tokens = tokens.dup
        loop { break unless shift_wrapper?(tokens) }
        tokens
      end

      # Shifts one leading wrapper (env, timeout, nice, time, bundle exec,
      # VAR=value, --) off the tokens; false once the head is the command.
      def shift_wrapper?(tokens)
        first = tokens.first
        if first&.match?(/\A[A-Za-z_]\w*=/) || first == "--"
          tokens.shift
        elsif %w[env /usr/bin/env].include?(first)
          tokens.shift
          skip_env_flags(tokens)
        elsif %w[timeout nice time].include?(first)
          tokens.shift
          skip_wrapper_operand(first, tokens)
        elsif first == "bundle" && tokens[1] == "exec"
          tokens.shift(2)
        else
          return false
        end
        true
      end

      # timeout skips its flags and duration; nice its adjustment (detached
      # -n 5/--adjustment 5 or glued -n5/--adjustment=5/legacy -5); time -p.
      def skip_wrapper_operand(wrapper, tokens)
        case wrapper
        when "timeout"
          tokens.shift while tokens.first&.start_with?("-")
          tokens.shift
        when "nice"
          tokens.shift(2) if %w[-n --adjustment].include?(tokens.first)
          tokens.shift if tokens.first&.match?(/\A-n\S|\A--adjustment=|\A-\d+\z/)
        when "time"
          tokens.shift if tokens.first == "-p"
        end
      end

      def skip_env_flags(tokens)
        tokens.shift while tokens.first&.start_with?("-") && !%w[-u -C].include?(tokens.first)
        tokens.shift(2) while %w[-u -C].include?(tokens.first)
      end

      # Redirections are shell syntax, not ruby operands: the operator and
      # its target ("2> errors.rb") or the glued form ("2>errors.rb",
      # ">out", "&>all") never count as scripts.
      REDIRECT_OPS = %w[> >> < 2> 2>> 1> 1>> &> &>>].freeze
      GLUED_REDIRECT = /\A\d*(?:>>?|<|&>)/

      # The operands after option parsing, script first: -e/-E/-r/-I/-C and
      # friends swallow their value.
      def script_operands(args)
        operands = []
        index = 0
        while index < args.size
          token = args[index]
          if REDIRECT_OPS.include?(token) || RUBY_OPERAND_OPTIONS.include?(token)
            index += 2
          elsif token.match?(GLUED_REDIRECT) || token.start_with?("-")
            index += 1
          else
            operands << token
            index += 1
          end
        end
        operands
      end
    end
  end
end
