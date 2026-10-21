# frozen_string_literal: true

Saboteur.configure do |c|
  c.include = ["lib/**/*.rb"]
  c.test_selection = :all # fixture layout does not follow spec naming; keep the whole suite
  c.operators = ["range"]
  c.timeout_min = 10 # wall-time floor: fork boot under load, not test speed (#1129)
end
