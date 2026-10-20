# copy_replacement

Drops a defensive copy, or makes a deep copy shallow. `x.dup` and `x.clone`
(no arguments, no block) become `x`; `x.deep_dup` becomes `x.dup`. The
receiver stays; only the call, or its name, changes. The fault it models is a
copy that is missing or too shallow, so the caller and the callee end up
sharing state that should be separate (a real hashie bug fixed `dup` to a deep
copy).

Runs by default. Use `--operators copy_replacement` to select it alone, or
`--exclude-operators copy_replacement` to leave it out. A survivor means no
test changes the copy, or the original, afterwards and looks at the other one:
add an example that mutates one side and asserts the other is untouched.
