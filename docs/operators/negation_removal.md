# negation_removal

Removes a logical negation: `!x` becomes `x`.

Runs by default. Use `--operators negation_removal` to select it alone, or
`--exclude-operators negation_removal` to leave it out. A survivor means the
tests never observe both polarities of the value - the negated and the plain
case behave the same on every input the tests try. Add the missing polarity,
or accept it when the value is fixed by construction.
