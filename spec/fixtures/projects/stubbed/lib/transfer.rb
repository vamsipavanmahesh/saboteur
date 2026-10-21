# SPDX-License-Identifier: MIT
# frozen_string_literal: true

class Transfer
  def fee(amount)
    amount * 2
  end

  # Exercised only through a stub in the project's spec: no test really
  # executes this method.
  def fx_rate
    1.25
  end
end
