# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # Lifecycle callbacks declared in config.
  #
  #   before_boot  - parent, before the target app is loaded
  #   after_boot   - parent, after the app and test files are loaded
  #   before_fork  - parent, once per mutant, just before fork
  #   after_fork   - child, right after fork (reconnect DBs, reseed RNG)
  #   around_mutant - child, wraps applying the mutant and running its tests
  class Hooks
    NAMES = %i[before_boot after_boot before_fork after_fork].freeze
    AROUND = :around_mutant

    def initialize
      @callbacks = Hash.new { |hash, key| hash[key] = [] }
    end

    def register(name, callable = nil, &block)
      name = name.to_sym
      raise ArgumentError, "unknown hook: #{name}" unless NAMES.include?(name) || name == AROUND

      @callbacks[name] << (callable || block || raise(ArgumentError, "hook #{name} needs a callable"))
      self
    end

    def run(name, *args)
      raise ArgumentError, "use #around for #{AROUND}" if name.to_sym == AROUND

      @callbacks[name.to_sym].each { |callback| callback.call(*args) }
      nil
    end

    # Each around_mutant callback receives the mutation and a proc that runs
    # the remaining chain. The first registered callback is the outermost.
    # Returns the block's result whatever the callbacks return; if a callback
    # never calls the chain, the block does not run and nil is returned.
    def around(mutation, &inner)
      result = nil
      body = -> { result = inner.call }
      chain = @callbacks[AROUND].reverse.reduce(body) do |next_step, callback|
        -> { callback.call(mutation, next_step) }
      end
      chain.call
      result
    end
  end
end
