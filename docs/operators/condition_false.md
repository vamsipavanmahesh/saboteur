# condition_false

Forces a condition to `false`: `if x` becomes `if false`. Also applies to
`unless` and loop conditions; the replacement that would make a loop never
end is skipped, since it could only produce a timeout.

Runs by default. Use `--operators condition_false` to select it alone, or
`--exclude-operators condition_false` to leave it out. A survivor means no
test distinguishes the condition being false from what it actually is -
usually the true case is missing. When the skipped branch has no observable
effect on the tested inputs, the mutant can be equivalent.
