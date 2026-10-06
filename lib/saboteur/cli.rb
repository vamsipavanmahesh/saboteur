# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "optparse"
require_relative "../saboteur"

module Saboteur
  class CLI
    USAGE = "Usage: saboteur run [--since REF] [--subject 'Klass#meth'] [--timeout-factor N] [--jobs N]"

    attr_reader :options

    def initialize(argv, out: $stdout, err: $stderr)
      @argv = argv.dup
      @out = out
      @err = err
      @options = {}
    end

    def call
      case @argv.shift
      when "run" then run
      when "version", "--version" then @out.puts(VERSION) || 0
      else usage_error
      end
    rescue OptionParser::ParseError => e
      usage_error(e.message)
    end

    private

    def usage_error(message = nil)
      @err.puts(message) if message
      @err.puts(USAGE)
      2
    end

    def run
      parser.parse!(@argv)
      @err.puts("saboteur #{VERSION}: run is not implemented yet")
      2
    end

    def parser
      OptionParser.new do |opts|
        opts.banner = USAGE
        opts.on("--since REF", "Only mutate subjects changed since git REF") { |v| options[:since] = v }
        opts.on("--subject EXPR", "Klass#meth or Klass.meth; repeatable") { |v| add_subject(v) }
        opts.on("--timeout-factor N", Float, "Multiple of baseline runtime (default 3)") { |v| set(:timeout_factor, v) }
        opts.on("--jobs N", Integer, "Concurrent workers (default 1)") { |v| set(:jobs, v) }
      end
    end

    def add_subject(expr)
      (options[:subjects] ||= []) << expr
    end

    def set(key, value)
      options[key] = value
    end
  end
end
