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

    Point = Data.define(:x, :y) do
      def above?
        y > x
      end

      def self.origin
        new(0, 0)
      end
    end

    Solo = Class.new do
      def one
        1
      end
    end

    Tally = Module.new do
      def tick
        :tock
      end
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
end
