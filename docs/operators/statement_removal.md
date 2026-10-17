# statement_removal

Replaces one statement with `nil`: `check; value` becomes `nil; value`. Only
sequences of two or more statements are touched. A single statement is
covered by `body_nil`, and expression slots (a ternary branch, an
interpolation, a modifier-`if` body) are covered by the condition operators,
so removing them would report the same gap twice. Removing a literal `nil`
and removing an `if`/`unless` without an `else` are skipped for the same
reason.

Runs by default. Use `--operators statement_removal` to select it alone, or
`--exclude-operators statement_removal` to leave it out. A survivor means the
statement's effect is invisible to the tests: a log line, a write nothing
reads, or a call whose result is never asserted. Pin the effect, or accept
the statement as unobservable.
