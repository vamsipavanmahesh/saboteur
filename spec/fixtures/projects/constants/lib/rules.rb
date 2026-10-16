# SPDX-License-Identifier: MIT
# frozen_string_literal: true

class Rules
  MAP = {
    city: "required",
    zip: "optional"
  }.freeze
  TAGS = %w[alpha beta].freeze

  def self.rule_for(field)
    MAP.fetch(field)
  end

  def self.tagged?(name)
    TAGS.include?(name)
  end
end
