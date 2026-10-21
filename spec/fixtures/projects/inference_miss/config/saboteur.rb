# frozen_string_literal: true

Saboteur.configure do |c|
  c.include = ["lib/**/*.rb"]
  # The spec/unit layout deliberately defeats the naming convention, so
  # inference misses and the run stops before boot (#658).
  c.timeout_min = 10 # wall-time floor: fork boot under load, not test speed (#1129)
end
