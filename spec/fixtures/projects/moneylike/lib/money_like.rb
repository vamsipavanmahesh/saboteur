# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# A minimal money-gem shape (RubyMoney/money): a value object and its
# allocation. The ranking regression fixture for #1160: the remainder
# finding from the C2 review must rank in the top 2 (#1144).
class MoneyLike
  attr_reader :cents

  def initialize(cents)
    @cents = cents
  end

  def +(other)
    MoneyLike.new(cents + other.cents)
  end
end
