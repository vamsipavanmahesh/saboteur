# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  module Reporter
    module Agent
      # Keeps display values short so the agent payload stays inside its byte budget.
      module Clipping
        # A seed or setting stays a number while it is short; a huge value cannot take the budget.
        def bounded_number(value)
          value.to_s.length <= MAX_NUMBER_DIGITS ? value : clip_value(value, MAX_NUMBER_DIGITS)
        end

        def clip_value(value, limit)
          return nil if value.nil?

          text = value.to_s
          text.length > limit ? "#{text[0, limit]}..." : text
        end

        def clip(text, limit)
          return "" if limit.zero?

          text.length > limit ? "#{text[0, limit]}..." : text
        end
      end
    end
  end
end
