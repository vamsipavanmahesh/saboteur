# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "did_you_mean"

module Saboteur
  # Loads config/saboteur.rb: a plain Ruby file of `Saboteur.configure`
  # blocks assigning settings on a strict object. It runs before the app
  # boots, so it cannot reference app constants - plain Ruby and ENV only.
  module ConfigFile
    # The assignment target. One setter per Config key; anything else is an
    # unknown setting.
    class Settings
      def initialize
        @values = {}
      end

      attr_reader :values

      (Config::DEFAULTS.keys - ["integration"]).each do |key|
        define_method("#{key}=") do |value|
          @values[key] = value
        end
      end

      def integration=(value)
        line = caller_locations(1, 1).fetch(0).lineno
        unless value.is_a?(String)
          raise ConfigError, "#{line}: integration must be a String, got #{value.inspect}; use \"rspec\""
        end

        @values["integration"] = value
      end

      # Repeatable per-path score gates (#473), the one setting that takes
      # arguments: c.score_gate "app/payments/**/*", min_score: 95. Values
      # are validated later, on the effective Config.
      def score_gate(pattern, min_score:)
        (@values["score_gates"] ||= []) << { "pattern" => pattern, "min_score" => min_score }
      end

      Config::INTEGER_KEYS.each do |key|
        define_method("#{key}=") do |value|
          unless value.is_a?(Integer)
            line = caller_locations(1, 1).first.lineno
            raise ConfigError, "#{line}: #{key} must be an Integer, got #{value.inspect}"
          end
          @values[key] = value
        end
      end

      Config::FLOAT_KEYS.each do |key|
        define_method("#{key}=") do |value|
          unless value.is_a?(Numeric)
            line = caller_locations(1, 1).first.lineno
            raise ConfigError, "#{line}: #{key} must be a number, got #{value.inspect}"
          end
          @values[key] = value
        end
      end

      Config::NILABLE_FLOAT_KEYS.each do |key|
        define_method("#{key}=") do |value|
          unless value.nil? || value.is_a?(Numeric)
            line = caller_locations(1, 1).first.lineno
            raise ConfigError, "#{line}: #{key} must be a number or nil, got #{value.inspect}"
          end
          @values[key] = value
        end
      end
    end

    module_function

    # The collector is process-global on purpose: the config file calls the
    # top-level Saboteur.configure, which must reach the load in progress.
    # Loads are therefore serialized - never load two config files at once.
    def load(path)
      # Kernel.load reports an unreadable file as "cannot load such file",
      # which reads like a typo'd path; say what actually happened.
      raise ConfigError, "cannot read the file - check its permissions" unless File.readable?(path)

      @settings = Settings.new
      Kernel.load(path)
      @settings.values
    rescue ConfigError => e
      raise ConfigError, "#{path}:#{e.message}"
    rescue NoMethodError => e
      raise ConfigError, unknown_setting_message(path, e) if e.receiver.is_a?(Settings) && e.name.to_s.end_with?("=")

      # A typo'd method call, not a setting: same treatment as a bare
      # constant, or the raw NoMethodError points at our internals.
      raise ConfigError, name_error_message(path, e)
    rescue SyntaxError, LoadError => e
      raise ConfigError, "#{path}: #{e.message.lines.first.to_s.chomp}"
    rescue NameError => e
      raise ConfigError, name_error_message(path, e)
    ensure
      @settings = nil
    end

    def unknown_setting_message(path, error)
      key = error.name.to_s.delete_suffix("=")
      suggestion = DidYouMean::SpellChecker.new(dictionary: Config::DEFAULTS.keys).correct(key).first
      hint = suggestion ? " (did you mean #{suggestion.inspect}?)" : ""
      line = error.backtrace_locations.find { |loc| loc.path == path }&.lineno
      "#{path}:#{line}: unknown setting #{key.inspect}#{hint}. " \
        "Valid settings: #{Config::DEFAULTS.keys.join(', ')}"
    end

    def name_error_message(path, error)
      line = error.backtrace_locations&.find { |loc| loc.path == path }&.lineno
      "#{path}:#{line}: #{error.message.lines.first.to_s.chomp} " \
        "- this file loads before the app boots; use plain Ruby or ENV"
    end

    private_class_method :unknown_setting_message, :name_error_message

    # The Settings block Saboteur.configure hands to the file being loaded.
    def current_settings
      @settings
    end
  end

  # Entry point used by config/saboteur.rb.
  def self.configure
    settings = ConfigFile.current_settings
    raise "Saboteur.configure is only valid while config/saboteur.rb loads" unless settings

    yield settings
    settings
  end
end
