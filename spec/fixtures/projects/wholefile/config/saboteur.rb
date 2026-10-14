# frozen_string_literal: true

Saboteur.configure do |c|
  c.include = ["lib/**/*.rb"]
  c.test_selection = :all # fixture layout does not follow spec naming; keep the whole suite
  c.whole_file = ["Doubled#*"]
end
