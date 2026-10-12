Saboteur.configure do |c|
  c.include = ["lib/**/*.rb"]
  c.sources = ["sources/hazard_source.rb:HazardSource"]
  c.timeout_min = 1
end
