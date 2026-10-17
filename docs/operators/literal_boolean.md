# literal_boolean

Swaps a boolean literal: `true` becomes `false` and `false` becomes `true`.
The wrong boolean can silently enable a setting or disable a validation.

Runs by default. Use `--operators literal_boolean` to select it alone, or
`--exclude-operators literal_boolean` to leave it out. A survivor means the
literal's value never changes anything the tests observe - a flag whose
effect is not asserted on either side. Add the case for the flipped value.
