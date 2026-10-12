Saboteur.configure do |c|
  c.include = ["lib/**/*.rb"]
  # A loaded CI runner can start a mutant's test process slower than the
  # 5 second default allows, which leaves the mutant unscored.
  c.timeout_min = 30
end
