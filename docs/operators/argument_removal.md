# argument_removal

Deletes one ordinary argument from a parenthesized method call. The call
stays intact, so a removed argument that the method never really needed
keeps the run green - the motivating fault shape is an incomplete preload
list, where the relation still works but a query-count guard would notice.

Runs by default. Use `--operators argument_removal` to select it alone, or
`--exclude-operators argument_removal` to leave it out. A survivor means the
argument's effect is invisible to the tests: a default that always applies
on the tested inputs, or an option nothing asserts. Pin the difference the
argument is supposed to make, or accept it with a reason. The design notes
are in [Positional argument removal](../argument-removal.md).
