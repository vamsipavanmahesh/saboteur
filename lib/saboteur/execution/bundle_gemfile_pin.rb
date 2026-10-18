# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "shellwords"

require_relative "test_command_shape"

module Saboteur
  module Execution
    # The test command's pinned BUNDLE_GEMFILE, or nil when it does not
    # set one. Every wrapper unwrap strips (VAR= words, env and its
    # flags, timeout, nice, time, bundle exec) keeps assignments in the
    # command's environment, so the prefix it removes is exactly the
    # assignment scope; the LAST BUNDLE_GEMFILE wins like the shell,
    # and an empty last value unsets (#722). A token like
    # A="x"BUNDLE_GEMFILE=g is one assignment to A and sets nothing.
    # Anything BUNDLE_GEMFILE-shaped the scan cannot prove refuses
    # rather than guessing the wrong Gemfile.
    module BundleGemfilePin
      # Raised when BUNDLE_GEMFILE shows up where the scan cannot prove it (#722).
      PIN_UNVERIFIABLE = "the test command sets BUNDLE_GEMFILE where its value cannot be verified; " \
                         "pin BUNDLE_GEMFILE as a leading assignment"

      # A pin value must be a literal: a substitution, tilde, glob, or
      # shell metacharacter makes it unknowable without running the shell (#722).
      PIN_UNVERIFIABLE_VALUE = /[$`\\~;&|<>()*?{}]/

      module_function

      def pinned_in(command)
        tokens = Shellwords.split(command)
      rescue ArgumentError
        raise ConfigError, PIN_UNVERIFIABLE if command.include?("BUNDLE_GEMFILE")
      else
        pin = pin_value(tokens)
        raise ConfigError, PIN_UNVERIFIABLE if pin == :unverifiable

        pin
      end

      # nil for no pin, :unverifiable for a BUNDLE_GEMFILE the scan
      # cannot prove, the literal value otherwise.
      def pin_value(tokens)
        prefix = tokens.first(tokens.size - TestCommandShape.unwrap(tokens).size)
        value = prefix.reverse.find { |word| word.match?(/\ABUNDLE_GEMFILE=/) }&.split("=", 2)&.last
        return :unverifiable if unverifiable_shape?(tokens, value)
        return nil if value.nil? || value.empty?
        return :unverifiable if value.match?(PIN_UNVERIFIABLE_VALUE)

        value
      end

      # BUNDLE_GEMFILE in a shape the scan cannot prove: env rewriting the
      # run's cwd or variables, or the pin outside the leading assignments.
      def unverifiable_shape?(tokens, value)
        mentioned = tokens.any? { |word| word.include?("BUNDLE_GEMFILE") }
        (mentioned && env_unverifiable?(tokens)) ||
          (value.nil? && tokens.any? { |word| word.match?(/(?:\A|[^A-Za-z0-9_])BUNDLE_GEMFILE=/) })
      end

      # env(1) carrying a cwd-repointing (-C/--chdir), word-reparsing
      # (-S/--split-string), or variable-unsetting (-u/--unset) flag: the
      # pin scan cannot prove the environment the command runs in (#722).
      def env_unverifiable?(tokens)
        tokens.each_index.select { |i| %w[env /usr/bin/env].include?(tokens[i]) }.any? do |i|
          tokens[(i + 1)..].take_while { |word| word.start_with?("-") }
                           .any? { |flag| flag.match?(/\A(?:-C|-S|-u|--chdir|--split-string|--unset)/) }
        end
      end
    end
  end
end
