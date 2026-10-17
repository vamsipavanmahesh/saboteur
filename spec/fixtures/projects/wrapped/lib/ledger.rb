# SPDX-License-Identifier: MIT
# frozen_string_literal: true

class Ledger
  attr_reader :entries, :log

  def initialize
    @entries = []
    @log = []
  end

  def record(amount)
    @log << "recording #{amount}"
    @entries << amount * 2
  end
end
