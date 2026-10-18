# frozen_string_literal: true

Saboteur.configure do |c|
  c.include = ["lib/plugins.rb"]
  c.test_selection = :all # fixture layout does not follow spec naming; keep the whole suite
end
