Saboteur.configure do |c|
  c.include = ["lib/**/*.rb"]
  # No arid patterns at suppression time, so the logging line is mutated and
  # its survivors carry the arid triage label.
  c.arid = []
end
