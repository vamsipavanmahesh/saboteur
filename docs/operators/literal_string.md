# literal_string

Empties a string literal: `"pending"` becomes `""`. Already-empty strings
and heredocs are left alone, and strings inside an interpolated string,
symbol or regular expression are not touched.

Runs by default. Use `--operators literal_string` to select it alone, or
`--exclude-operators literal_string` to leave it out. A survivor means the
string's content is never asserted - only its presence, or nothing at all.
Assert on the value, or accept the content as unobserved.
