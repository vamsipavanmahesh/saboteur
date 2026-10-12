# SPDX-License-Identifier: MIT
# frozen_string_literal: true

class BootValues
  def self.called; 123; end
  def self.uncalled; 456; end
  def self.endless_called = 789
  def self.endless_uncalled = 987
end

BOOT_VALUES = [BootValues.called, BootValues.endless_called].freeze
