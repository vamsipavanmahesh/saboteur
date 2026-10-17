# filter_replacement

Swaps the inclusion rule of a filter call with its exclusion rule:
`select` with `reject`, and `select!` with `reject!`. Only the message bytes
change; receiver, arguments and block stay intact. The fault it models is a
filter that keeps the items it should discard - or discards the ones it
should keep.

Runs by default. Use `--operators filter_replacement` to select it alone, or
`--exclude-operators filter_replacement` to leave it out. A survivor means
no test distinguishes the kept set from the dropped one - often because the
block is always true (or always false) on the tested inputs, so both rules
return the same thing. The design notes are in
[Filter polarity operators](../filter-operators.md).
