# literal_number

Changes a numeric literal: to one more, one less, and zero (skipping the
literal's own value).

Runs by default. Use `--operators literal_number` to select it alone, or
`--exclude-operators literal_number` to leave it out. A survivor means no
test pins the exact number - an off-by-one in a limit or threshold that the
suite only exercises far from the boundary. Test at and around the value.
