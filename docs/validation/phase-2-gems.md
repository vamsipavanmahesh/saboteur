# Phase 2: two public gems

Measured on 2026-10-09 (IST), macOS 14 (arm64, 14 cores), Ruby 3.3.4, jobs 1,
cold coverage cache. Targets and commits are pinned in `integration/targets.yml`.

| target | commit | spec examples | subjects | mutants |
|---|---|---|---|---|
| dry-inflector | b6a2819f | 1138 | 40 | 265 |
| tty-color | e2410967 | 60 | 17 | 136 |

## Results per re-evaluation strategy

| target | reeval | killed | survived | timeout | error | skipped | wall | mean per executed mutant | map build |
|---|---|---|---|---|---|---|---|---|---|
| dry-inflector | class_eval | 238 | 17 | 0 | 0 | 10 | 19.20 s | 0.046 s | 1.11 s |
| dry-inflector | nesting | 247 | 18 | 0 | 0 | 0 | 23.22 s | 0.058 s | 1.12 s |
| tty-color | class_eval | 25 | 1 | 0 | 0 | 110 | 0.53 s | 0.009 s | 0.06 s |
| tty-color | nesting | 122 | 13 | 0 | 0 | 1 | 2.11 s | 0.013 s | 0.06 s |

Wall time is saboteur's own measurement from boot to report and includes the
coverage map build. Per-mutant time is fork to result. The status counts were
identical on a repeat run.

Skips under `class_eval` are all `baseline failure`: the neutral check fails
because constants from enclosing modules (`Rules`, `Acronyms`, `NoValue`,
`TTY::Color` helpers) are not in lexical scope after `owner.class_eval`
(design 6.1). That is 10 of 265 mutants (3.8 %) on dry-inflector and 109 of 136
(80.1 %) on tty-color. `nesting` has no baseline failures on either gem. The one
remaining tty-color skip is a fine mutant skipped because a coarse mutant of the
same method survived.

## Survivors (nesting run), classified

Classes: real gap (a test is missing), equivalent (no observable behavior
change), noise (a tool defect). "Measured" means checked by running the mutant;
"read" means classified by reading the code and specs.

dry-inflector, 18 survivors: 9 real gaps, 9 equivalent, 0 noise.

| subject | mutation | class | basis |
|---|---|---|---|
| Defaults.plural | remove `([ti])a\z` rule | real gap: data -> datas | measured |
| Defaults.singular | remove `(tive)s\z` rule | real gap: objectives -> objectife | measured |
| Defaults.singular | remove `(shoe)s\z` rule | real gap: shoes -> sho | measured |
| Defaults.singular | remove `(database)s\z` rule | real gap: databases -> datababsis | measured |
| Defaults.singular | remove `(^analy)(sis\|ses)` rule | equivalent on analyses/analysis | measured |
| Defaults.singular | remove `(s)eries\z` rule | equivalent on series/movies | measured |
| Defaults.irregular | remove sex/sexes | equivalent: default rules give "sexes" | measured |
| Inflections#irregular | drop `uncountables.delete` (x2) | real gap: no test adds an irregular for an uncountable word | read |
| Inflections#rule | drop `uncountables.delete` (x2) | real gap: same, for plural/singular rules | read |
| Inflections#human | insert at -1 instead of 0 | real gap: rule precedence untested | read |
| Inflector#humanize | `match[0]` -> `match[1]`, `match[-1]` | equivalent: the one group spans the whole match | read |
| Inflector#underscore | `last_match(2)` -> `last_match(0)` | equivalent: group 1 is a zero-width lookbehind | read |
| Acronyms#initialize | drop `define_regex_patterns` | equivalent via public API: defaults always add acronyms | read |
| Acronyms#define_regex_patterns | `@rules.empty?` -> false | equivalent via public API, same reason | read |
| Inflections#initialize | `yield if block_given?` -> `if true` | equivalent via `Inflections.build`, which always passes a block | read |

tty-color, 13 survivors: 10 real gaps, 3 equivalent, 0 noise.

| subject | mutation | class | basis |
|---|---|---|---|
| Color#tty? | body -> nil | real gap: specs stub `tty?` everywhere | read |
| Mode#mode | `value = 8` -> 9, 7, 0 | equivalent: dead store, the loop always reassigns `value` | read |
| Mode#from_tput | `>= 8` -> `>= 7` | real gap: boundary untested (specs use 8 and 2) | read |
| Support#from_tput | `> 2` -> `> 3` | real gap: boundary untested | read |
| Support#support? | drop `return false if disabled?` (x2) | real gap: disabled with a TTY untested | read |
| Support#from_curses | drop Windows guard (x2) | real gap: Windows path untested | read |
| Support#from_curses | drop `curses_class \|\|= Curses`, `init_screen`, `close_screen` | real gap, low value: real curses path untested | read |

## Tool defects found and fixed

1. Statement removal fired on single-expression slots: ternary branches,
   string interpolation, modifier-if bodies. Those produced "replace with nil"
   mutants and duplicates of `condition_false`. Now it only applies to
   sequences of two or more statements. Effect: 40 fewer mutants
   (305 -> 265 on dry-inflector, 170 -> 136 on tty-color); 6 noise survivors gone.
   Trade-off: `break if cond` no longer gets a "drop the break" mutant;
   `condition_false` still covers the branch.
2. JSON report size: every mutant repeated full test names in `coveredBy`.
   Tests are now listed once under `testFiles` with short ids, and the file
   is written compact. dry-inflector report: 13.8 MB -> 1.27 MB.
   The coverage cache stores test indexes for the same reason.

Rejected candidate: rainbow, because its Gemfile pulls `mutant-rspec`, which the
clean-room rule does not allow us to install.
