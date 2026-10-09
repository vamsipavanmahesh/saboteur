# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/people"

class PersonTest < Minitest::Test
  def test_not_adult_at_17
    refute People::Person.new(17).adult?
  end

  def test_adult_at_19
    assert People::Person.new(19).adult?
  end

  def test_constant_comparison
    refute People::Person.new(17).adult_by_constant?
    assert People::Person.new(19).adult_by_constant?
  end

  def test_build
    assert_equal 40, People::Person.build(40).age
  end

  def test_describe_through_private_method
    person = People::Person.new(30)
    assert_equal "age 30", person.describe
    assert_includes person.private_methods, :label
  end
end
