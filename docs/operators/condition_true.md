# condition_true

Forces a condition to `true`: `if x` becomes `if true`. Also applies to
`unless` and loop conditions; the replacement that would make a loop never
end is skipped, since it could only produce a timeout.

Runs by default. Use `--operators condition_true` to select it alone, or
`--exclude-operators condition_true` to leave it out. A survivor means no
test distinguishes the condition being true from what it actually is -
usually the false case is missing. When the true branch has no observable
effect on the tested inputs, the mutant can be equivalent.
