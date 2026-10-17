# or_assign

Replaces `||=` with plain assignment: `x ||= 1` becomes `x = 1`, across
local, instance, class and global variables, constants, method calls and
index writes.

Runs by default. Use `--operators or_assign` to select it alone, or
`--exclude-operators or_assign` to leave it out. The mutant survives when
the receiver is never truthy at that point in the tests, so both forms
assign every time. That is often a memoization gap: add a case where the
value is already set and must be kept.
