# frozen_string_literal: true

Saboteur.configure do |c|
  c.include = ["lib/**/*.rb"]
  c.test_selection = :all # fixture layout does not follow spec naming; keep the whole suite
  c.sources = ["sources/hazard_source.rb:HazardSource"]
  c.timeout_min = 1
end
