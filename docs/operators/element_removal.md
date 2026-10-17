# element_removal

Deletes one element from an array literal, both in constants and inside
method bodies: `COLORS = [:red, :blue]` loses `:red`, and `allowed =
%w[get post]` inside a method loses `get`. Splat elements (`[*A, 2]`) and
heredocs are left alone, arrays inside arid statements (configured logging
and metrics calls) are not mutated, and elements inside a nested scope (a
`def`, class or module of their own) belong to that scope, not to the
enclosing subject.

Runs by default. Use `--operators element_removal` to select it alone, or
`--exclude-operators element_removal` to leave it out. A survivor means the
removed element changes nothing the tests assert: an element whose effect
duplicates another's, or a list the tests never check for membership or
completeness. A removed entry the tests should miss is a real gap.
