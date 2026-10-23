module Ledger
  class Transfer
    def initialize(amount) = @amount = amount

    def safe_ratio(other) = @amount / other
    rescue ZeroDivisionError
      0
  end
end
