# saboteur field-run config: human-essentials lane. CLI flags override.
Saboteur.configure do |c|
  c.include = ["app/**/*.rb", "lib/**/*.rb"] # user scope: app/ or lib/ Ruby
  c.require = ["./config/environment"]
  c.rails = true
  c.jobs = 1 # serial box rule
end
