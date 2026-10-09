# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Methods whose mutants misbehave on purpose (see sources/hazard_source.rb).
class Hazards
  def spin
    :spun
  end

  def crash_in_test
    :fine
  end

  def raise_on_load
    :fine
  end

  def die_on_load
    :fine
  end

  def reveal
    secret
  end

  private

  def secret
    :secret
  end
end
