# frozen_string_literal: true

Saboteur.configure do |c|
  c.include = ["lib/**/*.rb"]
  c.test_selection = :all # fixture layout does not follow spec naming; keep the whole suite
  c.sources = ["sources/hazard_source.rb:HazardSource"]
  c.timeout_min = 5 # floor above fork boot under load (#1169); only the hanging mutant waits it out
end
