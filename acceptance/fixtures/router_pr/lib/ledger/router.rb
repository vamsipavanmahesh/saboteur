class Router; def self.bank_for(amount) = amount > 5_000_000 ? :hdfc : :icici; end
