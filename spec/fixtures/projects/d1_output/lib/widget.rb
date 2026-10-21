# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Every method is exercised without an assertion on its result, so each one
# keeps surviving mutants: the default report must shorten exactly this
# shape (D1).
class Widget
  def one = 1 + 1

  def two = 2 + 2

  def three = 3 + 3

  def four = 4 + 4

  def five = 5 + 5
end
