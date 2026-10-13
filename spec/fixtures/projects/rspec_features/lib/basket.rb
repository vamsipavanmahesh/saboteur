# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# A small class whose specs use shared examples, aggregate_failures, pending
# examples and a persistence file, the RSpec features a real suite leans on.
class Basket
  def initialize(prices)
    @prices = prices
  end

  def total
    @prices.sum
  end

  def discounted(percent)
    total - (total * percent / 100)
  end

  def empty?
    @prices.empty?
  end

  def expensive?
    total > 100
  end
end
