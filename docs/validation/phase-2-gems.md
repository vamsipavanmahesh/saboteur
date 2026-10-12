# Phase 2: two public gems

> Measured before the coarse-survivor gate was removed and before the
> rebaseline. Mutant counts, skips and times here are historical; a rerun is pending.

Measured on 2026-10-09 (IST), macOS 14 (arm64, 14 cores), Ruby 3.3.4, jobs 1,
cold coverage cache. Targets and commits are pinned in `integration/targets.yml`.

| target | commit | spec examples | subjects | mutants |
|---|---|---|---|---|
| dry-inflector | b6a2819f | 1138 | 40 | 265 |
| tty-color | e2410967 | 60 | 17 | 136 |

## Re-measured after line-level selection (2026-10-09, commit after 4a24fed)

Same machine and commits. Changes since the first run: tests selected per
mutant by line, prior killers then fastest first, no removal of an
if/unless without else, kernel process table for containment.

| target | reeval | mutants | killed | survived | timeout | error | skipped | wall | mean per executed mutant |
|---|---|---|---|---|---|---|---|---|---|
| dry-inflector | class_eval | 261 | 235 | 17 | 0 | 0 | 9 | 21.75 s | 0.056 s |
| dry-inflector | nesting | 261 | 243 | 18 | 0 | 0 | 0 | 19.79 s | 0.046 s |
| tty-color | class_eval | 128 | 25 | 1 | 0 | 0 | 102 | 0.68 s | 0.013 s |
| tty-color | nesting | 128 | 116 | 11 | 0 | 0 | 1 | 2.40 s | 0.016 s |

Every run under script/watchdog: peak 4 processes, peak 176 MB total RSS, no
leftover processes. tty-color lost two survivors that were duplicates (the
Windows and `disabled?` guards were each reported by both statement removal
and `condition_false`). The classification below is from the first run;
the remaining survivors are the same mutants.

## Operator change M2 (sufficient ROR/COR sets, predicate coarse), before/after

Same commits, nesting, cold cache, under script/watchdog. Before = 20f80aa,
after = the M2 commit.

| target | | mutants | killed | survived | score | assertion kills | crash kills | wall |
|---|---|---|---|---|---|---|---|---|
| dry-inflector | before | 261 | 243 | 18 | 93.1 % | 160 | 83 | 21.93 s |
| dry-inflector | after | 267 | 249 | 18 | 93.3 % | 168 | 81 | 20.70 s |
| tty-color | before | 128 | 116 | 11 | 91.3 % | 88 | 28 | 2.45 s |
| tty-color | after | 136 | 118 | 16 | 88.1 % | 90 | 28 | 2.48 s |

Survivor sets, compared mutant by mutant (by location and mutated text):

- dry-inflector: identical survivors. No new noise.
- tty-color: 1 survivor gone, 6 new. All 6 are real gaps, read against the
  specs: `colors >= 8` -> `== 8` (more than 8 colours never tested);
  `!(no_color.nil? || no_color.empty?)` -> `!(no_color.nil?)` (empty NO_COLOR
  never tested); `` `tput colors`.to_i > 2 `` -> `!= 2` (fewer than 2 never
  tested); `windows?` -> `true` (Windows detection never checked);
  `tty?` -> `true` and -> `false` (replace the old `body_nil` survivor: the
  same gap, stated in both directions).

Decision: keep M2. The mutant count went up slightly (Ruby code here has
more connectors than comparisons, and each connector now yields 3 mutants
instead of 1), not down as in the Java studies; the new survivors were all
real gaps.

## Crash kills per operator (after M2, nesting)

A kill by a crash (NoMethodError, TypeError, ...) shows a test reached the
code, not that it checked the result. `body_raise` kills are crashes by
construction. Without `body_raise`, crash kills are 41 of 209 (20 %) on
dry-inflector and 11 of 101 (11 %) on tty-color.

dry-inflector (249 kills):

| operator | kills | by assertion | by crash | crash share |
|---|---|---|---|---|
| statement_removal | 110 | 88 | 22 | 20 % |
| body_raise | 40 | 0 | 40 | 100 % |
| body_nil | 39 | 33 | 6 | 15 % |
| literal_number | 32 | 22 | 10 | 31 % |
| condition_true | 9 | 6 | 3 | 33 % |
| condition_false | 9 | 9 | 0 | 0 % |
| boolean_logic | 8 | 8 | 0 | 0 % |
| body_true | 1 | 1 | 0 | 0 % |
| body_false | 1 | 1 | 0 | 0 % |

tty-color (118 kills):

| operator | kills | by assertion | by crash | crash share |
|---|---|---|---|---|
| literal_number | 29 | 29 | 0 | 0 % |
| statement_removal | 18 | 12 | 6 | 33 % |
| body_raise | 17 | 0 | 17 | 100 % |
| condition_true | 12 | 11 | 1 | 8 % |
| body_nil | 10 | 8 | 2 | 20 % |
| condition_false | 10 | 10 | 0 | 0 % |
| body_false | 6 | 6 | 0 | 0 % |
| body_true | 5 | 5 | 0 | 0 % |
| boolean_logic | 5 | 4 | 1 | 20 % |
| comparison | 3 | 3 | 0 | 0 % |
| negation_removal | 2 | 2 | 0 | 0 % |
| or_assign | 1 | 0 | 1 | 100 % |

Reading: statement removal and number literals kill by crashing most
often (a removed assignment leaves a nil; a changed index walks off an
array). Comparison, condition and connector mutants are killed by
assertions, which is what makes them the stronger signal.

## Parallel workers (--jobs), dry-inflector, nesting, cold cache

| jobs | wall | verdicts | peak processes | peak RSS | leftovers |
|---|---|---|---|---|---|
| 1 | 24.99 s | 249 killed, 18 survived | 3 | 191 MB | 0 |
| 14 | 7.24 s | identical, mutant by mutant | 30 | 1,125 MB | 0 |

Speed-up 3.45x on 14 cores. Wall time includes boot and the serial coverage
map build. The largest subject (Defaults.singular) runs on a single worker,
which caps the speed-up; splitting large subjects across workers is next.

## Incremental mode (--incremental), dry-inflector, nesting

| run | wall | verdicts reused | statuses | peak processes |
|---|---|---|---|---|
| first (empty cache) | 24.26 s | 0 of 261 | 243 killed, 18 survived | 3 |
| second (nothing changed) | 0.80 s | 261 of 261 | identical | 2 (no mutant child) |

Measured 2026-10-09 under script/watchdog, no leftovers either run.

## First run: results per re-evaluation strategy

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
