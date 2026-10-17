# chain_removal

Drops one link from the middle of a method chain: `a.b.c` becomes `a.c`. The
first receiver and the last call stay, so the result is still a call on the
original object. Calls that hand back their receiver or a copy of it
(`freeze`, `dup`, `clone`, `itself`, `tap`) are left alone by design, and a
chain that is the target of a write (`a.b.c = 1`) is not mutated.

Runs by default. Use `--operators chain_removal` to select it alone, or
`--exclude-operators chain_removal` to leave it out. A survivor can mean the
dropped link's effect is never asserted - or that the shorter chain is
equivalent across the intended inputs, in which case simplify the code or
accept it with a reason.
