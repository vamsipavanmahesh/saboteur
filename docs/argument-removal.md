# Positional argument removal

The motivating fault shape is an incomplete preload list:
`Model.includes(:a, :b, c: :d)` still returns a relation when one association
is removed, but a query-count guard can detect the missing preload. Deleting
the whole statement instead can fail for an unrelated reason.

`ArgumentRemoval` removes one ordinary positional argument per proposal. The
regression receiver accepts any preload list, so both changed calls execute
and an exact content assertion kills them. This is not an ActiveRecord query
measurement and does not promise that every generated mutant avoids a crash.

The first version handles parentheses. Keyword hashes, splats, forwarding and
arguments containing heredocs are skipped. Bracket indexing and assignment
syntax are not parenthesized calls; explicit `obj.[](:key)` is a call and is
eligible. Defaults, nested definitions and arid statements remain excluded.
Calls in callable bodies and nested argument expressions are visited. Commas
are located with Prism tokens, never a source-text comma search. The source
keeps comments and whitespace outside the removed argument and separator.

Builtin appends these fine proposals after the existing sources. Candidate
validation, deduplication, coarse-first order and the per-method cap are
unchanged. Earlier digests stay stable for unchanged subjects. The cap can
omit appended proposals, and additional mutants can change the score.

## Pinned integration migration

Linux Ruby 3.3.6, existing target configuration and pinned commits:

| Target / strategy | Before | After | Additions |
| --- | --- | --- | --- |
| dry-inflector nesting | 332 killed, 24 survived | 525 killed, 24 survived | 193 killed |
| dry-inflector class_eval | 324 killed, 23 survived, 9 error | 517 killed, 23 survived, 9 error | 193 killed |
| tty-color nesting | 127 killed, 20 survived, 3 skipped | 134 killed, 22 survived, 4 skipped | 7 killed, 2 survived, 1 ignored |
| tty-color class_eval | 140 killed+error, 7 survived, 3 skipped | 147 killed+error, 9 survived, 4 skipped | 7 killed+error, 2 survived, 1 ignored |

Nesting runs were compared by mutant id with this source enabled and disabled:
no old ids disappeared or changed verdict, and every addition is
`argument_removal`. No ignore entry was added. The default macOS tty-color
snapshot remains historical because this run did not measure macOS.

Commands: `ruby script/integration-target TARGET WORKDIR --reeval STRATEGY`.
