# boolean_logic

Changes a boolean connector: `a && b` becomes `a`, `b`, or `false`; `a || b`
becomes `a`, `b`, or `true` (likewise for `and` and `or`). The set is the
sufficient connector replacements (Just et al. 2012).

Runs by default. Use `--operators boolean_logic` to select it alone, or
`--exclude-operators boolean_logic` to leave it out. An operand mutant
survives when the dropped operand never changes anything the test observes -
one side is always truthy on the tested inputs. That can be a missing case
or genuinely dead defensive code; read the call sites before deciding.
