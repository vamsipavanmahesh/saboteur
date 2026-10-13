# SPDX-License-Identifier: MIT
# frozen_string_literal: true

class BootValues
  def self.called; 123; end
  def self.uncalled; 456; end
  def self.endless_called = 789
  def self.endless_uncalled = 987
  def self.shared_called; 3; end; def self.shared_uncalled; 4; end
end

BOOT_VALUES = [BootValues.called, BootValues.endless_called].freeze

BootValues.shared_called
