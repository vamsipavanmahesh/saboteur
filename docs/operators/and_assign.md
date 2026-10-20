# and_assign

Replaces `&&=` with plain assignment: `x &&= y` becomes `x = y`, across
local, instance, class and global variables, method calls and index writes.
Constants are mutated only in a `define_method` body: inside a def, `X = y` is
a syntax error, so that mutant could never run. The
fault it models is a guard that was dropped, so a value that was nil or
false gets assigned anyway.

Runs by default. Use `--operators and_assign` to select it alone, or
`--exclude-operators and_assign` to leave it out. The mutant survives when
the target is always truthy at that point in the tests, so both forms assign
every time. Add a case where the variable is nil or false and must stay so.
