Saboteur.configure do |c|
  c.include = ["lib/**/*.rb"]
  c.operators = ["operator_assignment"]
  c.timeout_min = 1
end
