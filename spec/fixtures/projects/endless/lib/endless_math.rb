# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Every def here is endless: line coverage never records a body hit, so
# before per-test method coverage these subjects were skipped (issue #107).
class EndlessMath
  def double(n) = n * 2

  def negate(n) = -n
end
