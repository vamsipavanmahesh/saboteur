# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module People
  ADULT_AGE = 18

  class Person
    attr_reader :age

    def initialize(age)
      @age = age
    end

    def adult?; @age >= 18; end

    def adult_by_constant?
      @age >= ADULT_AGE
    end

    def describe
      label
    end

    def self.build(age)
      new(age)
    end

    private

    def label
      "age #{@age}"
    end
  end
end
