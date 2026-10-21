# SPDX-License-Identifier: MIT
# frozen_string_literal: true

class Meter
  def self.reading=(value)
    @reading = value
  end

  def self.reading
    @reading
  end

  def self.over?
    (@reading || 0) > 100
  end
end
