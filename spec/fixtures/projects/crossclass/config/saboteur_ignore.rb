Saboteur.ignore do |i|
  # name is a Symbol here, and Symbol answers start_with? and length like the
  # String that to_s builds, so dropping the to_s call cannot change a result.
  i.mutation "979cb4136c0f4a88", subject: "Pieces::Ghost#method_missing",
                                 reason: "equivalent: Symbol#start_with? matches String#start_with?"
  i.mutation "7d1e262e6749057c", subject: "Pieces::Ghost#respond_to_missing?",
                                 reason: "equivalent: Symbol#start_with? matches String#start_with?"
  i.mutation "ceb6c9854f44a25b", subject: "Pieces::Ghost#helper",
                                 reason: "equivalent: Symbol#length matches String#length"
end
