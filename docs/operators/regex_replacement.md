# regex_replacement

Weakens a regex literal: drops one anchor (`\A`, `\z`, `\Z`, `^`, `$`) at a time, and swaps each `+` quantifier for `*` and each `*` for `+`. `/\A\d+\z/` yields `/\d+\z/`, `/\A\d*\z/` and `/\A\d+/`. Escaped characters, character classes, and lazy (`+?`) or possessive (`*+`) stacks stay untouched. Interpolated regexes get no mutants here: their bytes are not a stable 1:1 map. Arid expressions and nested definitions are skipped; the normal parser, dedupe and cap checks apply.

Runs by default. Use `--operators regex_replacement` to select it alone, or `--exclude-operators regex_replacement` to leave it out. A dropped anchor or widened quantifier survives when the test never probes the boundary: a validation spec that only tries one valid and one obviously-invalid string does not see `/\A\d+\z/` become `/\d+\z/`. Add a case that only the anchor rejects (a leading newline, surrounding text) rather than ignoring the survivor.

Closes the remaining slice of #135: regex literals previously got no mutants at all.
