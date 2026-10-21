# SPDX-License-Identifier: MIT
# frozen_string_literal: true

class Allocation
  def split(amount, parts)
    return amount if parts <= 1

    amount / parts
  end

  def remainder(amount, parts)
    amount - (amount / parts) * parts
  end
end
