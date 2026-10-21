# SPDX-License-Identifier: MIT
# frozen_string_literal: true

class Meter
  def self.over?
    (@reading || 0) > 100
  end

  def self.reading=(v)
    @reading = v
  end
end
