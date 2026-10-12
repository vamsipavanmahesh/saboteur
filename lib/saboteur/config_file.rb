# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "did_you_mean"

module Saboteur
  # Loads config/saboteur.rb: a plain Ruby file of `Saboteur.configure`
  # blocks assigning settings on a strict object. It runs before the app
  # boots, so it cannot reference app constants - plain Ruby and ENV only.
  module ConfigFile
    # The assignment target. One setter per Config key; anything else is an
    # unknown setting. Records the line of each assignment so validation
    # errors can point at it.
    class Settings
      def initialize
        @values = {}
        @lines = {}
      end

      attr_reader :values, :lines

      Config::DEFAULTS.each_key do |key|
        define_method("#{key}=") do |value|
          @values[key] = value
          @lines[key] = caller_locations(1, 1).first.lineno
        end
      end

      Config::INTEGER_KEYS.each do |key|
        define_method("#{key}=") do |value|
          unless value.is_a?(Integer)
            line = caller_locations(1, 1).first.lineno
            raise ConfigError, "#{line}: #{key} must be an Integer, got #{value.inspect}"
          end
          @values[key] = value
          @lines[key] = caller_locations(1, 1).first.lineno
        end
      end
    end

    module_function

    def load(path)
      @settings = Settings.new
      Kernel.load(path)
      @settings.values
    rescue ConfigError => e
      raise ConfigError, "#{path}:#{e.message}"
    rescue NoMethodError => e
      raise unless e.receiver.is_a?(Settings) && e.name.to_s.end_with?("=")

      raise ConfigError, unknown_setting_message(path, e)
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
