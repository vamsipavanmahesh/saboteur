# SPDX-License-Identifier: MIT
# frozen_string_literal: true

class Limits
  def self.min_ok?(amount)
    amount >= 100
  end

  def self.max_ok?(amount)
    amount <= 10_000
  end
end

class Checker
  RULES = [Limits.method(:min_ok?)]
  LATE = ->(amount) { Limits.max_ok?(amount) }

  def self.ok?(amount)
    RULES.all? { |rule| rule.call(amount) }
  end

  def self.late_ok?(amount)
    LATE.call(amount)
  end
end
