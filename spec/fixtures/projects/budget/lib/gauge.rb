# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Two small methods with mutants, so a stopped run has unreached subjects.
class Gauge
  def self.high?(level)
    level > 10
  end

  def self.label(level)
    high?(level) ? "high" : "low"
  end
end
