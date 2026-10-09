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
end
