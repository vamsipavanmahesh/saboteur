# comparison

Changes a comparison: swaps the operator (`a < b` becomes `a <= b`) or
replaces the whole comparison with `true` or `false`. The relational
replacements are the sufficient set (Kaminski, Ammann, Offutt 2011), so not
every pairing is generated. For `==` and `!=` only the literal replacements
run: `<=` on an object that is not Comparable raises, which would only give
cheap crash kills.

Runs by default. Use `--operators comparison` to select it alone, or
`--exclude-operators comparison` to leave it out. A swap survives when no
test exercises the boundary: a suite that only checks `a < b` and `a > b`
never sees `a == b`, where `<` and `<=` differ. Add the boundary case rather
than assuming the mutant is equivalent.
