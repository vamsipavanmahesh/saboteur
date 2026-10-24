Saboteur.configure do |c|
  c.include = ["app/**/*.rb", "lib/**/*.rb"]
  c.require = ["./config/environment"]
  c.rails = true
  c.jobs = 1
  c.baseline_timeout = 3600
end
