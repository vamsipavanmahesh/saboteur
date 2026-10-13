# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "../vendor/sorbet-runtime/lib/sorbet_runtime_shim"

class Fees
  extend T::Sig

  sig { params(amount: Integer).returns(Integer) }
  def typed_fee(amount)
    amount > 1000 ? 0 : 50
  end

  def untyped_fee(amount)
    amount > 1000 ? 0 : 50
  end
end
