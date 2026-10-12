# Hash and keyword pair removal

The fault shape is a missing nested preload association. Removing `c: :d`
from `Model.includes(:a, :b, c: :d)` keeps the call and positional associations
intact. The spec uses an accepting preload-like receiver and exact result
assertions. It is not a Rails SQL measurement or a guarantee that every
mutant runs without an arity/keyword error.

The source handles ordinary pairs in hash literals and keyword lists, including
command calls, sole pairs, trailing commas and block arguments. Keyword splats
remain. Heredoc-containing pairs, defaults, nested definitions and arid
statements are excluded. Separators use Prism tokens, lexed once per subject.
Builtin composition preserves the existing candidate pipeline and cap.

## Standalone pinned migration

Linux Ruby 3.3.6, current pinned targets and unchanged configurations:

| Target / strategy | Before | After |
| --- | --- | --- |
| dry-inflector nesting | 332 killed, 24 survived | 334 killed, 24 survived |
| dry-inflector class_eval | 324 killed, 23 survived, 9 error | 326 killed, 23 survived, 9 error |
| tty-color nesting | 127 killed, 20 survived, 3 skipped | 129 killed, 22 survived, 3 skipped |
| tty-color class_eval | 140 killed+error, 7 survived, 3 skipped | 142 killed+error, 9 survived, 3 skipped |

Nesting comparison by id preserves all earlier ids/verdicts; the only additions
are two killed pairs in dry-inflector and two killed/two surviving pairs in
tty-color. No new ignore entry. macOS tty-color remains its historical snapshot
because no macOS run was available. Commands:
`ruby script/integration-target TARGET WORKDIR --reeval STRATEGY`.

## Combined argument + pair migration

Measured with both sources active, same pinned targets on Linux Ruby 3.3.6:

| Target / strategy | Combined result |
| --- | --- |
| dry-inflector nesting | 527 killed, 24 survived |
| dry-inflector class_eval | 519 killed, 23 survived, 9 error |
| tty-color nesting | 136 killed, 24 survived, 4 skipped |
| tty-color class_eval | 149 killed+error, 11 survived, 4 skipped |

These combined results replace the standalone integration snapshots when both
sources are merged. Earlier standalone tables document separate experiments,
not the combined expected values. macOS remains unmeasured.
