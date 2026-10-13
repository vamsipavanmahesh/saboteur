# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Shapes
  class Money
    attr_reader :cents

    def initialize(cents)
      @cents = cents
    end

    def +(other)
      Money.new(cents + other.cents)
    end

    def -@
      Money.new(-cents)
    end

    def [](index)
      cents.digits[index]
    end

    def ==(other)
      cents == other.cents
    end
  end

  class First
    def label
      "first-#{1 + 1}"
    end
  end

  class Second
    def label
      "second-#{3 + 3}"
    end
  end

  class Conditional
    if RUBY_VERSION >= "1.9"
      def mode
        1 + 1
      end
    else
      def mode
        2 + 2
      end
    end
  end
end

class Shapes::Reopened
  def size
    4 * 2
  end
end
