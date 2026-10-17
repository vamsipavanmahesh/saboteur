# element_removal

Deletes one element from a constant array literal. Elements inside a nested
scope (a `def`, class or block of their own) belong to that scope, not to
the enclosing subject.

Runs by default. Use `--operators element_removal` to select it alone, or
`--exclude-operators element_removal` to leave it out. A survivor means the
removed element changes nothing the tests assert: an element whose effect
duplicates another's, or a list the tests never check for membership or
completeness. A removed entry the tests should miss is a real gap.
