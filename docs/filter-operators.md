# Filter polarity operators

## Fault reason

Keeping a set of items instead of removing it is a real Ruby fault, not just
an operator copied from another language. In Oxidized's command-replacement
work, [PR #2472](https://github.com/ytti/oxidized/pull/2472) includes a correction
named "Use reject! instead of select!". Its replacement
[PR #2486](https://github.com/ytti/oxidized/pull/2486) merged a `reject!` filter
that removes the existing command by name before appending its replacement.
The published change fixes `clear: true` deleting unrelated commands.

That history supports the destructive filter family directly. The
non-destructive `select` / `reject` pair models the same keep-versus-discard
fault without modifying the receiver. Its reason is that shared fault shape,
not a claim that this exact pair reproduces the entire Oxidized bug. Our specs
assert the intended contents of a two-element array and show that each of the
four replacements fails the same output assertion. No Oxidized code was copied.

## Scope and limits

- Swap `select` with `reject`, and `select!` with `reject!`, in both directions.
- Require an explicit receiver, a block (including `&predicate`), and no
  ordinary arguments. This excludes common SQL projection calls such as
  `relation.select(:name)` and unused Enumerator creation.
- Edit only the method-name bytes. Preserve `&.`, the block and its formatting.
- Keep the existing arid-statement and nested-definition boundaries.
- Append the new source's proposals after the old built-in proposals, keeping
  old digests and relative order for unchanged subjects. The candidate pipeline still re-parses and
  de-duplicates them, and applies the same coarse-first order and mutant cap.

The source uses `MutationSource::Base`; builtin composes it. The engine does
not acquire an operator-specific branch. The report operator and source name
are both `filter_replacement`.

No static type inference is attempted. A custom method with one of these names
can have a different contract or lack the replacement method. Those calls can
produce crash kills. This family is not proof of real-fault detection, and we
make no speed or score-improvement claim. Empty inputs can make a replacement
behavior-equivalent; it still runs under the existing policy. The bang methods
can also differ in their return value when no change is made.
