# Prior art survey and gap analysis

Status: research note, 2026-10-09 (IST). Read-only survey; no code changed.

Clean-room: no source, specs or fixtures of the Ruby `mutant` gem or of any
restrictively licensed tool were read. Sources are papers, talks and
user-facing documentation of permissively licensed tools. Where a claim is
from memory rather than a source read for this note, it says so.

Evidence markers used below:
- [read] figure taken from the paper/doc text during this survey.
- [abstract] figure taken from the abstract or venue page only.
- [memory] recalled, not re-checked; verify before quoting.
- [inference] my reasoning, not a published result.

Links: DOIs/URLs are given where checked. Entries without a link are from
memory (title and venue believed correct, DOI not checked).

---

## 1. Papers

### 1.1 Foundations

| paper | year, venue | finding | link |
|---|---|---|---|
| DeMillo, Lipton, Sayward, "Hints on Test Data Selection" | 1978, IEEE Computer | Coined mutation analysis; competent programmer + coupling effect hypotheses. | doi:10.1109/C-M.1978.218136 |
| Hamlet, "Testing programs with the aid of a compiler" | 1977, IEEE TSE | Independent origin of the idea. | [memory] |
| Offutt, "Investigations of the software testing coupling effect" | 1992, ACM TOSEM | Tests killing first-order mutants kill >99% of second-order ones: supports single-edit mutants. | [memory] |
| Howden, "Weak mutation testing and completeness of test sets" | 1982, IEEE TSE | Weak mutation: kill = state differs right after the mutated expression, not at the test oracle. | [memory] |
| Budd, Angluin, "Two notions of correctness and their relation to testing" | 1982, Acta Informatica | Mutant equivalence is undecidable in general. | [memory] |
| Jia, Harman, "An Analysis and Survey of the Development of Mutation Testing" | 2011, IEEE TSE | Standard survey up to 2010. | doi:10.1109/TSE.2010.62 |
| Papadakis et al., "Mutation Testing Advances: An Analysis and Survey" | 2019, Advances in Computers 112 | Survey 2008-2017; best single entry point for cost reduction and equivalence. | [memory] |
| Just et al., "Are mutants a valid substitute for real faults in software testing?" | 2014, FSE | Mutant detection correlates with real-fault detection beyond coverage; 73% of real faults coupled to common mutants. | doi:10.1145/2635868.2635929 [memory for 73%] |
| Papadakis et al., "Are mutation scores correlated with real fault detection?" | 2018, ICSE | Correlation is weak once test-suite size is controlled; mutant kill of specific "fault-revealing" mutants matters more than score. | [memory] |

Takeaway for saboteur: a survivor is a lead, not a verdict. The score is a
weak proxy; the per-survivor report is the product. That matches design 1.

### 1.2 Mutant reduction

| paper | year, venue | finding | link |
|---|---|---|---|
| Offutt, Rothermel, Zapf, "An experimental evaluation of selective mutation" | 1993, ICSE | Dropping the most prolific operators loses little adequacy. | [memory] |
| Offutt, Lee, Rothermel, Untch, Zapf, "An experimental determination of sufficient mutant operators" | 1996, TOSEM | 5 operators (ABS, AOR, LCR, ROR, UOI) approximate the full Mothra set (~99.5% score). | [memory] |
| Siami Namin, Andrews, Murdoch, "Sufficient mutation operators for measuring test effectiveness" | 2008, ICSE | Statistically chosen 28 operator subset, large reduction with accurate score prediction. | [memory] |
| Zhang, Hao, Zhang, Rothermel, Mei, "Is operator-based mutant selection superior to random mutant selection?" | 2010, ICSE | No: random sampling at equal mutant count is about as good. | [memory] |
| Kaminski, Ammann, Offutt, "Better predicate testing" | 2011, AST workshop | ROR: per relational operator, a subset of replacements subsumes the rest. | [memory]; cited in Just 2012 [read] |
| Just, Kapfhammer, Schweiggert, "Do redundant mutants affect the effectiveness and efficiency of mutation analysis?" | 2012, Mutation workshop (ICST) | Sufficient COR set: `a && b` -> `lhs`, `rhs`, `false`, `a == b`; `a \|\| b` -> `lhs`, `rhs`, `true`, `a != b`. The swap `&&`<->`\|\|` is subsumed. Holds for single-connector expressions (~78% of conditions in their subjects). Redundant mutants inflate scores; up to 34% runtime saving. | https://homes.cs.washington.edu/~rjust/publ/non_redundant_mutants_icst_2012.pdf [read] |
| Just, Kapfhammer, Schweiggert, "Using non-redundant mutation operators and test suite prioritization..." | 2012, ISSRE | Non-redundant COR/ROR: ~25% fewer mutants avg (up to 37%); with test prioritization/splitting, up to 65% less total cost. | https://homes.cs.washington.edu/~rjust/publ/mutation_test_prio_issre_2012.pdf [abstract] |
| Ammann, Delamaro, Offutt, "Establishing theoretical minimal sets of mutants" | 2014, ICST | Minimal (dominator) mutant set: a small subset determines the score of all. | [memory] |
| Kurtz et al., "Analyzing the validity of selective mutation with dominator mutants" | 2016, FSE | Classic selective sets score poorly on dominator mutants. | [memory] |
| Papadakis, Henard, Harman, Jia, Le Traon, "Threats to the validity of mutation-based test assessment" | 2016, ISSTA | Subsumed mutants distort the score; report on subsuming mutants. | [memory] |
| Gopinath, Alipour, Ahmed, Jensen, Groce, "On the limits of mutation reduction strategies" | 2016, ICSE | Smart selection beats random by only a small margin in theory and practice. | [memory] |
| Gopinath, Jensen, Groce, "How hard does mutation analysis have to be, anyway?" | 2015, ISSRE | A fixed random sample (order of 1,000 mutants) estimates the score well regardless of program size. | [memory] |

ROR sufficient sets as usually tabulated (Kaminski 2011, via Just 2012)
[memory, the Just 2012 paper confirms "four out of eight" replacements but I
did not extract the table]:

| original | sufficient replacements |
|---|---|
| `<`  | `<=`, `!=`, `false` |
| `<=` | `<`, `==`, `true` |
| `>`  | `>=`, `!=`, `false` |
| `>=` | `>`, `==`, `true` |
| `==` | `<=`, `>=`, `false` |
| `!=` | `<`, `>`, `true` |

### 1.3 Equivalent mutants

| paper | year, venue | finding | link |
|---|---|---|---|
| Offutt, Pan, "Automatically detecting equivalent mutants and infeasible paths" | 1997, STVR | Constraint-based; detects ~45% of equivalents in small programs. | [memory] |
| Grün, Schuler, Zeller, "The impact of equivalent mutants" | 2009, Mutation workshop | Mutants that change more of the run are less likely equivalent. | [memory] |
| Schuler, Zeller, "Covering and uncovering equivalent mutants" | 2013, STVR (ICST 2010 earlier) | ~45% of survivors were equivalent; "coverage impact" (mutant changes coverage) classifies non-equivalent with 75% precision, 56% recall; beats invariant-violation. ~15 min per manual classification. | https://www.st.cs.uni-saarland.de/publications/files/schuler-stvrbis-2013.pdf [abstract] |
| Madeyski et al., "Overcoming the equivalent mutant problem: a systematic literature review" | 2014, IEEE TSE | Detect, suggest, or avoid; avoidance at generation time is the cheap win. | [memory] |
| Yao, Harman, Jia, "A study of equivalent and stubborn mutation operators using human analysis of equivalence" | 2014, ICSE | Equivalence concentrates in a few operators/contexts. | [memory] |
| Papadakis, Jia, Harman, Le Traon, "Trivial Compiler Equivalence" | 2015, ICSE | Compile mutants with optimisation, compare binaries: >7% of all mutants equivalent, >21% duplicate; finds ~30% of real equivalents (C). | https://orbilu.uni.lu/bitstream/10993/20289/1/ICSE15.pdf [abstract] |
| Kintis et al., "Detecting trivial mutant equivalences via compiler optimisations" | 2018, IEEE TSE | TCE on Java: 5.7% equivalent, 5.4% duplicate; ~54% of Java ground-truth equivalents. | doi:10.1109/TSE.2017.2684805 [abstract] |
| Kushigian, Kaufman, Featherman, Potter, Madadi, Just, "Equivalent Mutants in the Wild" | 2024, ISSTA | Median equivalent rate 2.97% of mutants; most come from common code patterns detectable by AST pattern matching. 10 targeted rules (EMS) find 8,776 equivalents in 325 s vs TCE 2,124 in 2,938 h. | doi:10.1145/3650212.3680310 [abstract] |
| Tian et al., "Large Language Models for Equivalent Mutant Detection: How Far Are We?" | 2024, ISSTA (distinguished paper) | 3,302 Java mutant pairs; LLM approaches beat prior techniques by 35.69% F1 on average; fine-tuned code embeddings best. | https://arxiv.org/abs/2408.01760 [abstract] |

Calibration against saboteur Phase 2 [inference]: 12 equivalent of 401
mutants = 3.0%, in line with Kushigian's 2.97% median. As a share of
survivors it is 12/31 = 39%, close to Schuler-Zeller's ~45%. So saboteur's
noise is normal for the field; it is concentrated in survivors, which is what
developers see. That is where effort pays.

### 1.4 Execution: schemata, split-stream, weak mutation

| paper | year, venue | finding | link |
|---|---|---|---|
| Untch, Offutt, Harrold, "Mutation analysis using mutant schemata" | 1993, ISSTA | Compile all mutants into one meta-program, select at runtime: removes per-mutant compile cost. | [memory] |
| Just, Schweiggert, Kapfhammer, "MAJOR: an efficient and extensible tool for mutation analysis in a Java compiler" | 2011, ASE (tool) | Conditional mutation in javac + mutation coverage: run only mutants a test reaches. | [memory] |
| Just, Ernst, Fraser, "Efficient mutation analysis by propagating and partitioning infected execution states" | 2014, ISSTA | Skip tests for mutants that do not infect state; group mutants with equal infected state. | [memory] |
| Tokumoto et al., "MuVM: Higher order mutation analysis virtual machine for C" | 2016, ICST | Fork at the mutation point (split-stream) to share the common prefix. | [memory] |
| Wang et al., "Faster mutation analysis via equivalence modulo states" (AccMut) | 2017, ISSTA | Fork only when mutants produce distinct states at the mutation point; ~2-3x over schemata on C. | [memory] |
| Wang et al., "Faster mutation analysis with fewer processes and smaller overheads" (WinMut) | 2021, ASE | Refines fork-based split-stream. | [memory] |
| Stryker team, "Mutation switching" (StrykerJS 4) | 2020, blog | Schemata in JS: all mutants in one copy, toggle per run. | https://stryker-mutator.io/blog/mutation-switching/ [abstract] |

### 1.5 Test selection and prioritisation for mutants

| paper | year, venue | finding | link |
|---|---|---|---|
| Zhang, Marinov, Zhang, Khurshid, "Regression mutation testing" (ReMT) | 2012, ISSTA | Reuse prior mutant results across versions via dependency/change analysis. | [memory] |
| Zhang, Marinov, Khurshid, "Faster mutation testing inspired by test prioritization and reduction" | 2013, ISSTA | Order tests per mutant (e.g. tests that killed nearby mutants first, by runtime): large speedups without changing results. | [memory] |
| Chen, Zhang, "Speeding up mutation testing via regression test selection: an extensive study" | 2018, ICST | RTS tools applied to mutants cut cost; class/file-level selection is close to method-level. | [memory] |
| PIT documentation, FAQ | current | Per-test line coverage; drop tests that do not execute the mutated line; order remaining by increasing runtime. | https://pitest.org/faq/ [read] |

### 1.6 Predictive mutation testing

| paper | year, venue | finding | link |
|---|---|---|---|
| Zhang et al., "Predictive mutation testing" | 2016, ISSTA (TSE 2019 ext.) | Classifier predicts killed/survived from static + coverage features; good accuracy within project, weaker cross-project; big speedups. | [memory] |
| Mao et al., "An extensive study on cross-project predictive mutation testing" | 2019, ICST | Cross-project works with care; accuracy varies by project. | [memory] |
| Kim, Jeon, Yoo, "Predictive mutation analysis via natural language channel in source code" (Seshat) | 2022, TOSEM | Token-based prediction, no dynamic features. | [memory] |
| Jain et al., "Contextual predictive mutation testing" | 2023, FSE | Transformer predicts mutant-test kill pairs. | [memory] |

Applicability: requires per-language training data and still runs a model
per mutant. No Ruby datasets exist that I know of. Not recommended now.

### 1.7 Google, Meta: industrial practice

| paper | year, venue | finding | link |
|---|---|---|---|
| Petrović, Ivanković, "State of Mutation Testing at Google" | 2018, ICSE-SEIP | Diff-based mutation at code review, arid nodes, one mutant per line. | [memory] |
| Petrović, Ivanković, Kurtz, Ammann, Just, "An industrial application of mutation testing: lessons, challenges, and research directions" | 2018, ICSTW | Productive vs unproductive mutants; context matters. | https://people.cs.umass.edu/~rjust/publ/industrial_mutation_icst_2018.pdf [not read] |
| Petrović, Ivanković, Fraser, Just, "Practical Mutation Testing at Scale: A view from Google" | 2021, IEEE TSE | See facts below. | doi:10.1109/TSE.2021.3107634 [read] |
| Petrović, Ivanković, Fraser, Just, "Does mutation testing improve testing practices?" | 2021, ICSE-SEIP | Developers exposed to mutants write more tests over time. | [memory] |
| Beller et al., "What it would take to use mutation testing in industry: a study at Facebook" | 2021, ICSE-SEIP | Few, context-specific operators; developers want actionable, low-noise results. | [memory] |
| Chen, Salawa, Vijayvergiya, Petrović, Ivanković, Just, "MuRS: Mutant Ranking and Suppression using Identifier Templates" | 2023, FSE industry | Learns suppression/ranking from identifier templates and feedback. | https://research.google/pubs/murs-suppressing-and-ranking-mutants-with-identifiertemplates/ [title only] |
| Petrović, Ivanković, Fraser, Just, "Please fix this mutant: How do developers resolve mutants surfaced during code review?" | 2023, ICSE-SEIP | 38% of surfaced mutants resolved; 60% when a reviewer endorses ("Please fix"); 64% of mutants' code changed during review, so stable re-surfacing is non-trivial. | https://homes.cs.washington.edu/~rjust/publ/mutation_testing_resolution_icse_2023.pdf [abstract] |

Google TSE 2021, facts [read]:
- Only changed, covered lines in a changelist are mutated.
- Arid node: a simple node flagged by an "expert function", or a compound node
  all of whose children are arid. Over 100 rules; fuzzy name rules for 200+
  function families. Categories: uncompilable, equivalent, unproductive
  killable (most common), redundant.
- Biggest gains came from three early heuristics: logging, time-related code
  (deadlines, timeouts, backoff), configuration flags. Memoization/cache
  lookup is listed as an equivalent-mutant source.
- Unsound heuristics (name matching) gave more usefulness than sound,
  type-based ones.
- At most one mutant per line: "the vast majority of mutants for a given line
  share the same fate".
- Unproductive share fell from 85% to 11%; productivity measured via "Please
  fix"/"Not useful" links: 82% overall, 80% -> 89% over time.
- Median 7 mutants per changelist vs 820 traditional.
- 87.5% of generated mutants killed. LCR survives ~2x as often as UOI. ROR,
  LCR and SBR (statement block removal) similarly productive; AOR and UOI
  noticeably less. ABS dropped (nonsensical on time/count values).
- Context-based (historical) operator selection: +40% survival, +~50%
  productivity probability vs random.
- Mutants must be stable across snapshots so the same mutant is reported again.

### 1.8 Extreme / coarse mutation

| paper | year, venue | finding | link |
|---|---|---|---|
| Niedermayr, Juergens, Wagner, "Will my tests tell me if I break this code?" | 2016, CSED (ICSE workshop) | "Pseudo-tested methods": body removal undetected despite coverage; common even in well-tested code. | [memory] |
| Vera-Pérez, Monperrus, Baudry, "Descartes: a PITest engine to detect pseudo-tested methods" | 2018, ASE tool | Extreme mutation: replace body with typed defaults (void -> empty, bool -> true/false, numbers -> 0/1, null, empty string/array). Far fewer mutants than PIT defaults. | doi:10.1145/3238147.3240474 |
| Vera-Pérez, Danglot, Monperrus, Baudry, "A comprehensive study of pseudo-tested methods" | 2019, EMSE | Replicated on 28K+ methods: pseudo-tested methods exist in all subjects; developers often would not pay to fix them. | doi:10.1007/s10664-018-9653-2 [abstract] |

Note for saboteur: Descartes's value comes from typed defaults, especially
`true` and `false` for boolean methods. saboteur's coarse set is untyped
(`nil`, `raise`), so a predicate method whose tests only check the falsy
case is never caught by `body -> nil`.

### 1.9 Dynamic languages

| paper | year, venue | finding | link |
|---|---|---|---|
| Mirshokraie, Mesbah, Pattabiraman, "Efficient JavaScript mutation testing" | 2013, ICST | Rank by function importance/usage to cut equivalents in JS. | [memory] |
| Derezińska, Hałas, "Analysis of mutation operators for the Python language" | 2014, DepCoS-RELCOMEX | Many classic operators yield type-incompetent mutants in dynamic languages, killed only by crashes. | [memory] |
| Gopinath, Walkingshaw, "How good are your types? Using mutation analysis to evaluate the effectiveness of type annotations" | 2017, ICSTW | Mutants a type checker rejects: type annotations act as a mutant filter. | [memory] |

Evidence for Ruby specifically is thin. I found no peer-reviewed study of
mutation testing on Ruby. The general observation for dynamic languages
[memory, weak]: a share of "killed" mutants die by `NoMethodError`/`TypeError`
rather than an assertion. Those inflate the score and say little about test
quality.

### 1.10 Learned and LLM-based mutants

| paper | year, venue | finding | link |
|---|---|---|---|
| Tufano et al., "Learning how to mutate source code from bug-fixes" | 2019, ICSME | NMT trained on reversed bug fixes produces realistic mutants. | [memory] |
| Patra, Pradel, "Semantic bug seeding" (SemSeed) | 2021, FSE | Learned bug patterns adapted to new contexts. | [memory] |
| Degiovanni, Papadakis, "μBERT: Mutation Testing using Pre-Trained Language Models" | 2022, Mutation workshop (ICST) | Mask a token, let CodeBERT fill: natural mutants. | [memory] |
| Tian et al., "Learning to construct better mutation faults" (LEAM) | 2022, ASE | Grammar-guided learned mutants. | [memory] |
| Tip, Bell, Schäfer, "LLMorpheus: Mutation Testing using Large Language Models" | 2024 arXiv (TSE version 2025, unverified) | Placeholder prompting on JS; mutants resembling real bugs that StrykerJS cannot produce. | https://arxiv.org/abs/2404.09952 [abstract] |
| Wang, Chen, Lin, Harman, Papadakis, Zhang, "A Comprehensive Study on Large Language Models for Mutation Testing" | 2024-2026 arXiv (v5 Jan 2026) | 851 real Java bugs: LLM mutants detect real faults far better (87.98% vs 41.64% rule-based, v4) but are worse on non-compilability (+26.6 pp), duplication (+10.1 pp), equivalence (+3.5 pp). Numbers differ between versions. | https://arxiv.org/abs/2406.09843 [abstract] |
| Dakhel et al., "Effective test generation using pre-trained LLMs and mutation testing" (MuTAP) | 2024, IST | Feed survivors to the LLM to generate killing tests. | [memory] |
| Foster, Gulati, Harman et al., "Mutation-Guided LLM-based Test Generation at Meta" (ACH) | 2025, FSE industry | Concern-directed LLM mutants (privacy) + LLM tests to kill them; 10,795 Kotlin classes, 9,095 mutants, 571 tests; engineers accepted 73% of tests, 36% judged privacy-relevant. LLM also used as equivalence filter [memory]. | https://arxiv.org/abs/2501.12862 [abstract] |

Measured usefulness: strong evidence that LLM mutants are more "real-fault
like"; weak evidence on developer usefulness of the mutants themselves. The
one deployment number (Meta 73%) measures accepted tests, not mutant
reports. Cost per mutant is orders of magnitude above a byte edit.

---

## 2. Tools

Execution column: how a mutant gets into the running program.

| tool (license) | language | execution | test selection | incremental | noise control | reporting |
|---|---|---|---|---|---|---|
| PIT / pitest (Apache-2.0) | JVM | Bytecode mutated in memory; class re-written after load in long-lived "minion" JVMs; never on disk [read]. No fork per mutant. | Per-test line coverage; only tests executing the mutated line; sorted by runtime, matching test class weighted up [read]. | History file: reuse killed if class and killing test unchanged; survived if no new/changed covering tests; retry last killer first. Documented as potentially wrong, "currently unproven" assumption on dependencies [read]. | Static initializer and inlined `finally` filters; mutator groups DEFAULTS/STRONGER/ALL (ALL discouraged) [read]. Commercial add-ons exist (Arcmutate); not examined. | HTML, XML, CSV. |
| Descartes (LGPL; PIT engine) | JVM | Via PIT. | Via PIT. | Via PIT. | Extreme mutation: typed method-body defaults; reports pseudo-tested / partially-tested methods. | Method-level report. |
| Major (see project) | Java | Conditional mutation compiled into javac output (schemata). | Mutation coverage; test prioritisation by runtime. | No [memory]. | Non-redundant COR/ROR; EMS equivalence rules (2024) [abstract, via UW blog]. | CSV/log. |
| StrykerJS / Stryker.NET / Stryker4s (Apache-2.0) | JS/TS, C#, Scala | Mutation switching (schemata): all mutants in one build, one active per run [abstract]. | Per-test coverage ("perTest") [memory]. | `--incremental`: git-like diff of code and tests vs `stryker-incremental.json`; reuse Killed if culprit test unchanged, else reuse if no new covering test and no changed tests; ignores dependency/env changes [read]. | TypeScript checker drops type-invalid mutants; static mutants (run at load) handled separately; `// Stryker disable` comments; mutation levels [memory]. | mutation-testing-elements HTML + JSON schema; states Killed/Survived/NoCoverage/Timeout/CompileError/RuntimeError/Ignored; score = detected/valid and also on covered code [read]. Dashboard. |
| mutmut 3 (BSD) | Python | Parent imports pytest, runs suite once for stats, then forks one child per mutant; `forkserver` mode [read]. Trampoline dispatch per function [read: name only; mechanism not documented]. | Stats from the initial run decide which tests are relevant; optional stack-depth limit [read]. | Re-tests only mutants in functions whose source changed; resumable; warns on dependency changes; `cache_invalidation_files` [read]. | `# pragma: no mutate` (line/block/region), `do_not_mutate_patterns`, `mutate_only_covered_lines` [read]. | Terminal, TUI browser. |
| Cosmic Ray (MIT) | Python | AST mutation, mutated module per worker, distributed workers; session in SQLite [memory]. | Runs configured test command (no per-test selection by default) [memory]. | Session resume [memory]. | Filters: pragma, git diff, operator filters [memory]. | HTML/reports from session DB. |
| mutatest (MIT) | Python | Writes mutated bytecode to `__pycache__`, runs pytest [memory]. | None per mutant. | No. | Random location sampling [memory]. | Text. |
| cargo-mutants (MIT) | Rust | Text-span edits on a copied tree, build, test, revert; one scratch tree per job [read]. | Whole `cargo test` (no per-test selection) [read]. | `--in-diff` (mutants overlapping a diff); `--iterate` skips previously caught/unviable (heuristic; do a full run at the end) [read]; `--shard k/n` for CI. | Function body -> typed defaults (`()`, `true`/`false`, `0/1/-1`, `Ok(..)`, `Default::default()`); unviable (compile-fail) reported separately; `#[mutants::skip]`, `exclude_re` [read]. | `mutants.out/` with outcomes.json, caught/missed lists, diffs; exit codes per class [read]. |
| Infection (BSD) | PHP | AST mutation; mutated file loaded in place of the original by an include interceptor [memory]. | Per-test coverage via Xdebug/PCOV; only covering tests; ordered by runtime [memory; intro doc confirms "tests that cover changed line" read]. | Git diff filter options [memory]. | Regex source ignores per mutator [memory]. | MSI, Mutation Code Coverage, Covered-code MSI [read]; counts errors as detected [read]; Stryker dashboard. |
| Mull (Apache-2.0) | C/C++ | LLVM IR mutants compiled in with runtime switches (schemata) [memory]. | Runs test binary per mutant [memory]. | No [memory]. | "Junk" detection: drop mutants not mappable to source AST [memory]. | Text/IDE/Elements JSON [memory]. |
| Dextool mutate (MPL-2.0) | C/C++ | Schemata + source mutants; SQLite DB [memory]. | Test-case analysis per mutant [memory]. | Yes, DB-backed, re-tests changed code [memory]. | Equivalence via TCE-style compare [memory, weak]. | HTML. |
| go-mutesting / Gremlins (MIT/Apache) | Go | Rewrite file, `go test` per mutant; Gremlins: parallel workdirs [memory]. | Gremlins uses coverage to mark NOT COVERED without running [memory]. | No. | Gremlins: skip uncovered. | Text/JSON. |
| Universal Mutator (MIT) | many | Regex text rewrites; TCE-style dedupe by comparing compiled output [memory]. | External command. | No. | TCE. | Text. |
| Heckle (MIT, historic) | Ruby 1.8 | ParseTree-based method mutation in process [memory]. | Named tests. | No. | None. | Text. |
| mutant (commercial for private use) | Ruby | Not examined (clean-room rule). | - | - | - | - |

Closest analogues to saboteur's core: cargo-mutants (text-span edits, coarse
typed body replacement, baseline-then-mutants) and mutmut 3 (fork per mutant
from a parent that loaded the test framework once). PIT/Infection/Stryker
define the norm for per-mutant test selection and incremental reuse.

---

## 3. Gap analysis

saboteur today (from design.md, engine.rb, builtin.rb, coverage_map.rb):
- Prism byte-range edits; re-parse guard; text de-dup.
- Fork per mutant; re-eval one method; neutral check; supervisor with
  process-tree kill and limits.
- Coverage map by line, but tests are selected per SUBJECT (union over all
  body lines), ordered by suite order; fail-fast in rspec.
- Coarse first (`nil`, `raise`); fine: ROR swaps, `&&`<->`||`, negation drop,
  condition true/false, AOR swap, number +-1/0, statement removal, `&.`,
  `||=`.
- Arid regexes on statement source.
- `--since` selects subjects whose line range intersects the diff.
- Ignore list with mandatory reason; Stryker JSON; terminal diffs.
- No result cache; no per-mutant NoCoverage; jobs = 1.

Ranked by (impact x confidence) / cost. "Core conflict" checks against:
byte-range edits, one-method re-eval per forked child, coverage-based
selection, coarse-first.

### G1. Per-mutant test selection by mutated line, with NoCoverage status

- What: select tests covering the line where the mutated node's enclosing
  statement starts, not the union over the method. If none, status
  `no_coverage` without forking (Stryker NoCoverage; Gremlins NOT COVERED).
- Why it is sound [inference]: if the statement holding the mutated node is
  never executed by a test, the mutant cannot change that test's run up to
  that point, and never reaches it afterwards. Caveat: Ruby `lines` coverage
  records line events at statement starts; a mutated node on a continuation
  line of a multi-line expression has no event of its own. Map each edit to
  the first line of its innermost enclosing statement node; if that line has
  no entry in the map, fall back to subject-level tests. Coarse mutants keep
  subject-level tests. Optional later: `Coverage.setup(branches: true)` gives
  per-branch counts, which separates `if`/`else` arms on one line.
- Impact: speed proportional to method length and test fan-in (small on
  dry-inflector's short methods, larger on long Rails methods; measure).
  Signal: "no test reaches this line" becomes its own message instead of a
  generic survivor.
- Cost: low (map already has per-line ids; add node->line mapping in Builtin
  or Engine; new status in reporters; Stryker `NoCoverage` already mapped).
- Core conflict: none; strengthens coverage-based selection.
- Sources: PIT FAQ [read]; Stryker metrics [read]; Infection intro [read].

### G2. Per-mutant test ordering: last killer first, then fastest

- What: record per-test runtime during the map build (one clock read per
  test in Recorder). Per subject, keep the ids that killed earlier mutants;
  run them first, then remaining tests by ascending runtime. Fail-fast does
  the rest.
- Impact: speed on killed mutants, which are ~90% of executed mutants in
  Phase 2 (369 of 400). Zhang 2013 and Just ISSRE 2012 report large cost cuts
  from prioritisation (up to 65% combined with non-redundant operators).
  Gain shrinks when one test already covers the subject.
- Cost: low. Map format bump (runtime per test) or a separate timing file.
- Core conflict: none. The "executed == requested" guard (design 6.4) must
  compare sets, not order.
- Sources: PIT FAQ [read]; Zhang et al. ISSTA 2013 [memory]; Just et al.
  ISSRE 2012 [abstract].

### G3. Operator set: sufficient ROR/COR and typed coarse mutants

- ROR now: `<` -> `<=`, `>`. Sufficient set: `<=`, `!=`, `false`. `<` -> `>`
  is killed by any test with a != b, so it is subsumed by `!=` and inflates
  the score. Proposed table as in 1.2, with a Ruby change for `==`/`!=`:
  `<=`/`>=` on non-Comparable values raise `NoMethodError` (trivially killed,
  [inference]); use `false` and `true` instead. `!=` for `==` is then
  redundant (subsumed by both).
- COR now: `&&` <-> `||` only. Sufficient: `a && b` -> `a`, `b`, `false`;
  `a || b` -> `a`, `b`, `true`. Drop `a == b`/`a != b` (Ruby truthiness: not
  boolean equivalence). `x = opts[:k] || default` -> `x = opts[:k]` is the
  "default never tested" mutant, very common in Ruby; the current swap to
  `&&` finds the same gap less directly.
- Caveat: the subsumption proofs assume boolean operands and a single
  connector (78% of conditions in Just 2012's Java subjects). Ruby operands
  are arbitrary objects. Treat as a hypothesis; measure mutant count, score
  and survivor classes on the Phase 2 gems before and after.
- Typed coarse (Descartes, cargo-mutants): for `def x?` add `body -> true`
  and `body -> false` (replace `nil` for predicates: `nil` and `false` are
  both falsy, `true` is missing entirely). For a body whose last expression
  is an Array/Hash/String/Integer literal or ends in `.to_a`/`.map`/`.select`,
  add `[]`/`{}`/`""`/`0`. Keep `raise`.
- Impact: signal-to-noise up (fewer subsumed mutants, stronger ones); likely
  mutant count down 15-35% on comparison/boolean-heavy code (Java numbers;
  Ruby unmeasured). Predicate `true` should find real gaps of the
  "specs only check the false case" kind.
- Cost: low (Builtin only). Changes digests of affected mutants: ignore-list
  entries for removed mutants turn stale (already warned).
- Core conflict: none; all are byte-range edits. Coarse-first keeps working;
  note a predicate `-> true` survivor will skip all fine mutants, which is
  the intended behaviour.
- Sources: Just et al. 2012 Mutation workshop [read]; Kaminski 2011
  [memory]; Descartes 2018; cargo-mutants book [read]; Google TSE 2021 (ROR,
  LCR, SBR most productive; AOR, UOI least) [read].

### G4. Ruby equivalence rules at generation time (EMS / arid expert function)

- What: a small rule set, AST pattern based, applied before a mutant exists.
  Candidates from Phase 2 and the literature:
  1. Memoization: `@x ||= expr` (and `return @x if defined?(@x)`): the
     `or_assign` mutant is equivalent unless tests count calls or depend on
     identity. Google lists memoization as an equivalent source [read].
  2. Dead stores: a local written and overwritten before any read (Phase 2
     `Mode#mode value = 8`, 3 equivalent survivors). Skip literal mutations
     on dead stores, and report the dead store as a code finding instead.
  3. Arithmetic/literal mutations inside arid contexts already covered;
     extend arid defaults with time/timeout/backoff and config-flag patterns
     (`sleep`, `timeout:`, `retry`, `ENV.fetch` defaults), Google's top three
     sources of unproductive mutants [read].
  4. Index literals into MatchData (`m[0]`, `last_match(n)`) and into the
     result of a regex with one group: Phase 2 equivalents. Weak, specific;
     consider only after more data.
- Impact: survivors are where noise is visible; Phase 2 had 12 equivalent of
  31 survivors. Rules 1-2 would have removed 3 of 12 there [inference];
  rule 1 has no Phase 2 example (frequency in Rails apps unknown, likely
  high).
- Cost: low-medium per rule; each needs a fixture and a regression spec.
  Unsound rules are acceptable if listed (Google: unsound rules gave the
  bigger usefulness gains [read]).
- Core conflict: none.
- Sources: Kushigian et al. ISSTA 2024 [abstract]; Google TSE 2021 [read];
  Yao et al. ICSE 2014 [memory].

### G5. Diff mode that matches code review

- What: with `--since`, keep coarse mutants for touched subjects but limit
  fine mutants to changed lines (cargo-mutants `--in-diff`, Google). Add an
  optional "one surviving mutant per line" report filter and a PR-annotation
  output (GitHub `::warning file=..,line=..` lines or SARIF).
- Impact: usefulness. Google: median 7 mutants per change vs 820; 38% of
  surfaced mutants resolved, 60% with reviewer endorsement [read/abstract].
- Cost: low (GitDiff already returns changed lines).
- Core conflict: none. Coarse-first still operates per subject.
- Caveat: "one per line" hides detail on the line; keep the full list in the
  JSON report.

### G6. Incremental result cache

- What: store each result keyed by mutation digest plus a hash of the
  subject text, the killing test's file (if killed) or all covering test
  files (if survived), lockfile and config. Reuse rules as PIT/Stryker:
  killed -> reuse if killer test file unchanged (or re-run killer first, the
  only lossless PIT optimisation [read]); survived -> reuse if no covering
  test file changed and no new covering test.
- Impact: speed on repeat runs (CI, local loops). Correctness risk: changes
  in callees/collaborators are invisible. PIT calls its assumption
  "currently unproven"; Stryker and cargo-mutants document the same hole
  [read]. Make it opt-in or pair it with periodic full runs.
- Cost: medium (cache store, invalidation, reporting "cached").
- Core conflict: none.

### G7. Survivor triage by infection (weak-mutation probe)

- What: in the neutral-check child and in each surviving mutant's child,
  record a digest of the subject's return value / raised class per call
  (prepend a wrapper on the owner after re-eval). Classify survivors:
  "not infected" (same outputs on every call: likely equivalent, or inputs
  never hit the difference) vs "infected, not detected" (outputs differ but
  tests pass: an assertion is missing). Rank the second group first.
- Evidence: Schuler-Zeller coverage impact: 75% precision for non-equivalent
  [abstract]; Just-Ernst-Fraser 2014 uses infection to skip tests [memory].
  Ruby-specific evidence: none.
- Cost: medium. Value digests are the hard part (`inspect` can be large or
  side-effecting; `Marshal` fails on procs/IO). Needs a size cap and a
  "not comparable" bucket. Also only sees the subject's return, not
  ivar/state changes (`Inflections#rule` style mutants would look
  "not infected" when they are real gaps): use as ranking, never to hide.
- Core conflict: none (runs inside the forked child; extra overhead only on
  survivors, which are re-run once).

### G8. Reporting

- HTML via the mutation-testing-elements web component over the existing
  JSON (low cost).
- Label coarse survivors "pseudo-tested method" (Niedermayr/Descartes
  vocabulary), and show "covered by N tests".
- Record whether a kill came from an assertion failure or from an exception
  raised in the subject (`NoMethodError`, `TypeError`); report the
  crash-killed share per operator. Dynamic-language concern; evidence weak
  [memory]; cost low (rspec failure exception class is available).
- Report both score and covered-code score (Stryker/Infection) once G1 exists.
- Cost: low. No conflict.

### G9. Parallel jobs

- Already planned (Phase 5). Fork-per-mutant makes it straightforward for
  libraries; Rails needs one DB per worker (TEST_ENV_NUMBER-style). Linear
  speedup up to cores; the largest raw speed lever. Cost medium-high for
  Rails. No conflict.

### G10. Sampling for large codebases

- `--sample N` per subject or global random sample (Zhang 2010; Gopinath
  2015: random is about as good as operator selection and a fixed-size
  sample estimates the score). Useful for a first run on a big Rails app.
  Cost low. No conflict; coarse mutants should always run.

### G11. LLM hooks (opt-in, via the existing MutationSource and a new triage hook)

- Most promising use is not generation but triage: classify survivors as
  likely-equivalent, and draft a killing test (MuTAP, Meta ACH). Evidence
  for equivalence detection is Java-only (Tian 2024). Generation via the
  MutationSource plug-in is possible today; expect higher non-compilable/
  NameError rates (re-parse catches syntax only) and higher cost
  (Wang et al. [abstract]). Concern-directed prompts (Meta: privacy) are the
  part with deployment evidence.
- Cost: medium. Data concern: sends source to a third-party API; must stay
  opt-in and documented. No core conflict.

### G12. Iseq-level duplicate/equivalence check (TCE analogue)

- Compile each mutated method with `RubyVM::InstructionSequence.compile`
  and compare against the original and earlier mutants.
- Expected yield low [inference]: YARV's optimiser is a peephole pass; it
  will not remove dead stores or prove `x.size >= 0`. TCE's yield depended
  on gcc -O3. Cost is low (ms per mutant), so worth one measurement on the
  Phase 2 gems; drop if it finds < 1%.
- No conflict.

### Rejected or deferred

| technique | why not (for saboteur) |
|---|---|
| Mutant schemata / mutation switching | Removes per-mutant compile cost. saboteur's per-mutant cost is fork + test run (13-58 ms per mutant in Phase 2); re-eval of one method is a small part [inference; measure re-eval alone before reconsidering]. Schemata add a branch to every call of the subject and still need isolation. |
| In-process hot-swap without fork (PIT minion style) | Conflicts with fork-per-mutant isolation, which Ruby needs (class-level caches, globals, monkey patches leak between mutants). |
| Split-stream (fork at first call of the subject) | Would share expensive test setup, but a fork in the middle of a test shares the open DB connection and transaction with the parent; unusable for Rails tests [inference]. Large complexity for an unmeasured gain. |
| Predictive mutation testing | Needs training data per language; none for Ruby; cross-project accuracy varies. |
| Higher-order mutants | More cost, no evidence of usefulness in developer-facing tools. |
| LLM mutant generation by default | Cost, non-determinism, data handling; evidence supports realism, not developer usefulness of the reports. |

---

## 4. Evidence quality notes

- Strongest: Google TSE 2021 (large deployment, developer feedback), PIT/
  Stryker/cargo-mutants docs (what mature tools do), Just 2012 COR table.
- Moderate: TCE and EMS numbers (C/Java; transfer to Ruby unknown);
  Schuler-Zeller (small sample, 140 mutants).
- Weak for Ruby: every operator-subsumption argument (boolean semantics),
  crash-kill inflation, all LLM numbers (Java/JS/Kotlin; versions of
  Wang et al. disagree).
- Not verified here: rows marked [memory]. Verify DOIs before citing them
  in public docs.
