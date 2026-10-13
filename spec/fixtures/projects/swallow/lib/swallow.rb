# SPDX-License-Identifier: MIT
# frozen_string_literal: true

class Producer
  def value
    21 * 2
  end
end

# Swallows every StandardError, so a raising mutant of Producer#value must
# still be noticed through the real answer the spec expects.
class Consumer
  def safe_value
    Producer.new.value
  rescue StandardError
    :fallback
  end
end
