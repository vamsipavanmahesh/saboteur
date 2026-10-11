# Literal operator expansion

## Audit and next batch

Before this batch, builtin covers whole-body nil/raise (true/false for predicate
methods), comparisons, arithmetic +/− and */÷, boolean connector operands and
constants, numeric ±1/zero, statement removal, condition constants, negation
removal, safe navigation removal and ||= replacement. The filter source in
PR #17 is separate work and is not required by this batch.

The MIT [mutineer README](https://github.com/davidteren/mutineer) lists
boolean_literal among its default families, and string_literal,
condition_negation, regex and collection_method among optional families.
This audit reads only that public list, not operator implementations. No
commercial mutant source or documentation was consulted.

Priority is a small literal batch with direct assertions, then separately
investigate collection-empty and call-family replacements. Regex mutation
needs its own validity and useful-fault policy. Conditional negation deserves
measurement before adding it: condition true/false and existing negation
removal already exercise many of the same gaps.

## Fault reasons

- `literal_boolean`: swap true and false, in either direction. Wrong boolean
  values can silently enable a setting or disable validation. The
  [OpenAPI Ruby fix #21943](https://github.com/OpenAPITools/openapi-generator/pull/21943)
  describes API false becoming true through coercion/defaults. The
  [yard-lint config fix](https://github.com/mensfeld/yard-lint/commit/efa4abd9c88633e43f45ffab0c7b014e44d33060)
  describes explicit false being ignored in favor of a truthy default.
- `literal_string`: replace a nonempty static string with an empty string.
  Empty tokens and versions hit different paths than meaningful text:
  [Ruby JWT #640](https://github.com/jwt/ruby-jwt/pull/640) fixes empty-token
  handling, and [Dependabot #9471](https://github.com/dependabot/dependabot-core/pull/9471)
  fixes empty-version errors. This operator checks whether a test distinguishes
  a chosen nonempty literal from the empty-input boundary.

These are fault-shape reasons, not claims that our mutants reproduce those
entire historical bugs. The specs show exact return/content assertions that
kill each replacement, not measured real-fault detection improvements.

## Generation contract

The new `LiteralReplacement < MutationSource::Base` is composed by builtin
and appends fine proposals after earlier operators. Boolean edits use
`literal_boolean`; string edits use `literal_string`; both report source
`literal_replacement`. All edits are byte ranges and the usual candidate
re-parse, text de-duplication, coarse-first order and per-method cap apply.

Only the method body is visited. Default parameters and nested definitions
are not changed. Arid statements remain excluded. Strings must be nonempty
static quoted or percent strings with an opening delimiter; empty strings,
heredocs, interpolation (including its embedded expressions), word/symbol
lists, symbols, regexes and command strings are left alone. The replacement
is the ordinary Ruby `""` literal. Its spelling or encoding can differ from
the original string; this is a deliberate mutation, not an equivalence claim.
Ruby's literal syntax is documented at
[the Ruby 3.3 literal reference](https://ruby-doc.org/3.3.0/syntax/literals_rdoc.html).

For unchanged subjects, old proposals retain their relative order and digests.
The candidate pipeline can remove duplicates and the cap may hide appended
proposals, so there is no guaranteed increase for every method. Runs can
contain more mutants and have different scores. No performance claim is made.
If a method reads its own source or observes frozen strings or encodings, its
behavior can also change. Accepted-survivor lists may need review, not silent
blanket acceptance.

## Snapshot migration

Linux Ruby 3.3.6, pinned integration projects, unchanged configuration:

| Project / strategy | Before | After | New proposals |
| --- | --- | --- | --- |
| dry-inflector nesting | 249 killed, 18 survived | 332 killed, 24 survived | 89 |
| dry-inflector class_eval | 241 killed, 17 survived, 9 error | 324 killed, 23 survived, 9 error | 89 |
| tty-color nesting (Linux) | 116 killed, 18 survived, 2 skipped | 127 killed, 20 survived, 3 skipped | 14 |
| tty-color class_eval | 127 killed+error, 7 survived, 2 skipped | 140 killed+error, 7 survived, 3 skipped | 14 |

The nesting baseline and new run were compared by mutant id: all old mutants
remain and retain their verdicts. All additions carry only the two new operator
names. dry-inflector adds 80 killed strings, 6 surviving strings and 3 killed
booleans; tty-color adds 7 killed strings, 4 killed booleans, 2 surviving
booleans and one ignored string. The ignored string comes from the target's
existing ignore policy, not a new saboteur ignore entry. CI's class_eval
snapshot still compares killed+error where those counts fluctuate.

Commands: `ruby script/integration-target NAME WORKDIR --reeval STRATEGY --check`
with NAME dry-inflector or tty-color, STRATEGY nesting or class_eval.
The default tty-color nesting snapshot is still its historical macOS baseline:
no macOS integration run was available here. The measured Linux override is
updated (including skipped), not an invented macOS total. The CI integration
jobs run on Linux. A macOS snapshot refresh remains explicit follow-up.
