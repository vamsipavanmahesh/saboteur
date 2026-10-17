# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module ReevalTargets
  LIMIT = 18

  class Person
    def initialize(age)
      @age = age
    end

    def adult?
      @age >= LIMIT
    end

    def greeting
      "hi"
    end

    def call_secret
      secret
    end

    def compare(other)
      other.guarded
    end

    def self.make(age)
      new(age)
    end

    # define_method bodies are subjects too (#194): re-evaluating the whole
    # call redefines the method on the enclosing class.
    define_method(:dm_doubled) do |n|
      n * 2
    end

    class << self
      def factory
        :factory
      end

      private

      def hidden_factory
        :hidden
      end
    end

    private

    def secret
      :secret
    end

    protected

    def guarded
      :guarded
    end
  end

  module Util
    module_function

    def twice(value)
      value * 2
    end
  end

  class Priced
    def total
      10
    end
    alias sum total
    alias amount total

    private

    def secret_total
      1
    end
    alias hidden_sum secret_total
  end

  # An alias taken before the method was redefined keeps the older body on
  # purpose; it is not an alias of the current definition.
  class Redefined
    def total
      10
    end
    alias original_total total

    def total # rubocop:disable Lint/DuplicateMethods
      20
    end
  end
end

module ReevalTargets
  module PrivateCopies
    module_function

    def hidden
      :original
    end
    private_class_method :hidden

    def protected_copy
      :original
    end
    singleton_class.send(:protected, :protected_copy)

    def public_contract
      [hidden, protected_copy]
    end
  end

  # `X = Data.define(...) do` / `Struct.new` subjects (#290): re-evaluated
  # through X.class_eval, never by reopening the generated class.
  Point = Data.define(:x) do
    def doubled
      x * 2
    end
  end

  Pair = Struct.new(:a, :b) do
    def total
      a + b
    end
  end

  Tools = Module.new do
    def self.version
      1
    end
  end

  module Outer
    SCALE = 10

    Meter = Data.define(:n) do
      def scaled
        n * SCALE
      end
    end
  end

  # A factory nested in a factory block: the constant assignment is lexical,
  # so Coin lives on ReevalTargets, never on the generated Bag class (#339).
  Bag = Class.new do
    # rubocop:disable-next Lint/ConstantDefinitionInBlock -- the pattern under test
    Coin = Data.define(:cents) do
      def doubled
        cents * 2
      end
    end
  end
end
