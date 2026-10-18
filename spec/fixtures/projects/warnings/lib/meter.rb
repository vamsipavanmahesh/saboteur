# SPDX-License-Identifier: MIT
# frozen_string_literal: true

class Meter
  def reading(raw)
    raw > 100 ? raw - 10 : raw
  end
end
