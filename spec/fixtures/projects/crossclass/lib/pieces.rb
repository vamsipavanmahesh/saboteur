# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "forwardable"

module Pieces
  class Leaf
    def value
      10 + 5
    end
  end

  class Middle
    def total
      Leaf.new.value * 2
    end
  end

  class Top
    def report
      Middle.new.total + 1
    end
  end

  class Base
    def greeting
      "hello"
    end
  end

  class Child < Base
    def greeting
      super + " world"
    end
  end

  module Shout
    def shout(text)
      text.upcase + "!"
    end
  end

  class Speaker
    include Shout
  end

  module Wrapping
    def render
      "<" + super + ">"
    end
  end

  class Plain
    prepend Wrapping

    def render
      "x"
    end
  end

  class Backend
    def fetch
      40 + 2
    end
  end

  class Delegating
    extend Forwardable
    def_delegator :@backend, :fetch

    def initialize
      @backend = Backend.new
    end
  end

  class Ghost
    def method_missing(name, *)
      return helper(name) if name.to_s.start_with?("ghost_")

      super
    end

    def respond_to_missing?(name, _include_private = false)
      name.to_s.start_with?("ghost_")
    end

    def helper(name)
      name.to_s.length + 100
    end
  end

  class Version
    include Comparable
    attr_reader :number

    def initialize(number)
      @number = number
    end

    def <=>(other)
      number <=> other.number
    end
  end

  class Worker
    def compute
      Thread.new { 6 * 7 }.value
    end
  end

  class Counter
    def self.start
      100 + 1
    end
  end

  class Dsl
    def self.build(&block)
      new.instance_eval(&block)
    end

    def double(number)
      number * 2
    end
  end

  class Lazy
    HANDLER = ->(n) { Lazy.bump(n) }

    def self.bump(number)
      number + 1000
    end

    def self.call(number)
      HANDLER.call(number)
    end
  end
end
