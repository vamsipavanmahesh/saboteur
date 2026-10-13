# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# One method per way Ruby hides a method. Each body adds one to SEED, and the
# specs call it without checking the value, so a mutant of the body survives
# only while the spec still sees the method as hidden as it was written.
SEED = 1

class Hidden
  def public_value = SEED + 1

  private

  def private_value = SEED + 1

  protected

  def protected_value = SEED + 1

  public

  def inline_private_value = SEED + 1
  private :inline_private_value

  private def private_def_value = SEED + 1

  def self.class_private_value = SEED + 1
  private_class_method :class_private_value

  class << self
    def singleton_public_value = SEED + 1

    private

    def singleton_private_value = SEED + 1
  end

  def run_hidden
    [private_value, inline_private_value, private_def_value, self.class.send(:class_private_value),
     self.class.send(:singleton_private_value)]
  end

  def compare(other) = other.protected_value
end

module Helper
  module_function

  def function_value = SEED + 1

  def self_extended_probe = SEED + 1
end

module SelfExtended
  extend self

  def open_value = SEED + 1

  private

  def closed_value = SEED + 1
end
