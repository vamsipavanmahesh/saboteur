# safe_navigation

Replaces safe navigation with a regular call: `x&.name` becomes `x.name`.

Runs by default. Use `--operators safe_navigation` to select it alone, or
`--exclude-operators safe_navigation` to leave it out. A survivor means no
test passes `nil` for the receiver. That is usually a missing nil case; it
can also be impossible by construction, when the receiver is always built
just above. Check which one it is before writing the test or the ignore
entry.
