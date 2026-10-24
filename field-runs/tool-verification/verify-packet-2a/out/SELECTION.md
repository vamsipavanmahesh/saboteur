# Sample selection provenance

Pool: all 36 killed mutants from the 5 serial producer reports (2231=4, 2204=19, 2156=6, 2090=7, 2182=0), frozen as pool-killed.txt
pool-killed.txt   SHA256 bfe86e3f0e0fb7969bbd065a57bdd3157ec1fbd6e1f6eca1e9c9368a1256e0d1

Algorithm (verbatim, Ruby):
  pool = File.readlines("pool-killed.txt").map(&:strip).reject(&:empty?)
  pool.shuffle(random: Random.new(20261023)).first(10)

Selection: selection-10.txt
selection-10.txt  SHA256 a6965326be01d21fd04c7877d726a8d73311134666a088b43f7e0f2c35e7134b
Selected: 2204x7 (e4679d48, 04d20954, 829cfe49, c48b2d39, 26b630df, f638f3e4, 65f55d1d), 2156x1 (5e66e0c9), 2231x1 (a40b6c22), 2090x1 (11436dd3)

Pool frozen AFTER all 5 producer reports parsed (no hand-picking).
