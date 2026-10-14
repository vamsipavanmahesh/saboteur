Saboteur.configure do |c|
  c.include = ["lib/**/*.rb"]
  c.operators = ["condition_negation"]
  c.timeout_min = 1
end
