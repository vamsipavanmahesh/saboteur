# Verification config WITHOUT the EX-1 exclusion: additional whole-existing
# confirmation after the targeted spec verified GREEN on this tree.
Saboteur.configure do |c|
  c.include = ["app/**/*.rb"]
end
