# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# A ledger whose only tests live in an integration spec: nothing named
# ledger_spec.rb exists, so name inference alone cannot find them.
class Ledger
  def fee(amount)
    amount * 2
  end
end
