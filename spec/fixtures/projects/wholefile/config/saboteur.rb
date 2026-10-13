Saboteur.configure do |c|
  c.include = ["lib/**/*.rb"]
  c.whole_file = ["Doubled#*"]
end
