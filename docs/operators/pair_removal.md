# pair_removal

Deletes one pair from a hash literal or keyword argument list:
`Model.includes(:a, :b, c: :d)` loses `c: :d`. The call and its positional
arguments stay intact, so the fault a missing pair models is subtle - the
relation still works, only the preloading is gone.

Runs by default. Use `--operators pair_removal` to select it alone, or
`--exclude-operators pair_removal` to leave it out. A survivor means the
pair's effect is invisible to the tests: a key whose value nothing reads, or
a nested preload no query guard covers. The design notes are in
[Hash and keyword pair removal](../pair-removal.md).
