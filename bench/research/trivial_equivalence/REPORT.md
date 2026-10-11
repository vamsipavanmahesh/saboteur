# Spike: does an instruction-sequence comparison find equivalent Ruby mutants?

Status: research only. Nothing here is wired into the engine, and no
suppression feature ships from it. No runtime decision should rely on this
judge. Roadmap Milestone 2 asked for a measured yes or no for this strategy.

## Verdict

**No, for this strategy on these workloads.** The comparison found a matching
fingerprint for 0 of 9,178 builtin mutants across hashie, saboteur and lobsters,
at both identity levels. A hit rate of 0% leaves nothing to ship, and the roughly
30% reported for C programs (Papadakis et al., 2015) did not appear for
saboteur's operators on CRuby 3.3.

Recommendation: do not build compiler-equivalence suppression.

Separate hypothesis, not supported by this measurement: checks on the Prism
tree for narrow, provable patterns (for example a changed literal inside a
branch that a constant condition removes) might find some equivalents. This
spike measured nothing about them. If they are pursued, they need their own
definition and measurement.

## What a match means

The harness compiles the whole original file and the whole mutated file with
`RubyVM::InstructionSequence.compile`, normalizes both, and compares the
results as trees. A **match** means the two normalized fingerprints are equal.
It does not prove the two programs behave the same. Anything else, including a
compile error on either side, is **no match**, and a no-match mutant always
runs.

What the fingerprint keeps and drops:

| Part of the sequence | Compared? | Notes |
|---|---|---|
| Instructions and every operand (literals, constant and method names, call flags, branch targets) | yes | the literal pool lives in the operands, so a changed literal differs |
| Nested sequences (blocks, methods, class bodies, rescue and ensure bodies) | yes, recursively | |
| Catch (exception) table with its nested sequences | yes | rescue, ensure, retry, break, next |
| Local variable table and parameter description | yes | a rename is a difference |
| Sequence type, label, stack and local sizes | yes | |
| File paths, node ids, code columns | no | see exclusions |
| Line numbers | strict: yes. relaxed: no | see below |

Two levels:

- **strict** keeps line numbers.
- **relaxed** drops line numbers, and gives no match for a file that contains
  one of a list of reflective calls (`caller`, `binding`, `eval`,
  `source_location`, `__LINE__`, `method`, `define_method`, `send`, `RubyVM`,
  `TracePoint`, `set_backtrace` and similar; the list is in
  `reflection_scan.rb`).

### Observation model, and what it excludes

A match is meaningful only under this restricted model: behavior that is
visible through the instructions, their operands, the exception table and the
local table. It explicitly does not cover:

- **Backtrace line numbers in relaxed mode.** An ordinary `raise` exposes line
  numbers. A relaxed match accepts that. (A spec shows a shifted `raise` still
  matches at the relaxed level.)
- **Code locations and node ids in both modes.** They are dropped, but
  error_highlight, `RubyVM::AbstractSyntaxTree.of` and tracing tools can
  observe them.
- **Callers and readers outside the file.** The reflection list scans only the
  file under test. Another file can call `caller`, read this file's source, or
  inspect a method with `source_location`, and the scan would not see it.
- **Anything that reads its own source text**, such as `File.read(__FILE__)`.
- **The file-local denylist** is a list of names, not a guarantee.

## Pin

`CompilerPin` enforces the pin rather than recording it: the compile options
are passed explicitly (not read from interpreter defaults), and compiling on a
Ruby series other than 3.3 raises. Results were measured on CRuby 3.3.6
(2024-11-05 revision 75015d4c1f), x86_64 Linux, with peephole_optimization,
specialized_instruction, operands_unification and inline_const_cache on;
instructions_unification, tailcall_optimization and coverage_enabled off;
frozen_string_literal as set by each file's magic comment. A different Ruby or
option set can compile differently, so these results do not carry over to it.

## Results

| Workload | Files | Mutants | Strict matches | Relaxed matches | Relaxed: reflective file | Matched but killed |
|---|---:|---:|---:|---:|---:|---:|
| hashie `lib/**/*.rb` | 41 | 1,645 | 0 | 0 | 1,251 | 0 |
| saboteur `lib/**/*.rb` | 43 | 3,589 | 0 | 0 | 1,368 | 0 |
| lobsters `app/models/*.rb`, `lib/**/*.rb` | 49 | 3,944 | 0 | 0 | 1,684 | 0 |
| **Total** | 133 | **9,178** | **0** | **0** | 4,303 | **0** |

"Matched but killed" is the wrong-skip count. **It is vacuous**: with no
matches, no mutant would have been skipped, so zero says nothing about
whether a match is safe. The only evidence about match behavior is the spec
file, which has controls where the compiler itself removes the change (a
changed branch behind `if true`, a changed statement behind a modifier
`if false`) and cases where it keeps it (a changed statement after `return`).

Survival data, not equivalence truth: on hashie, 400 mutants drawn at random
(seed 1) were run against the 719-example suite, and 72 survived (18.0%). An earlier
run of the same sample, before a per-mutant timeout was added, counted 66
survivors, so the survivor count has run-to-run variance of a few mutants. A
mutant whose suite run exceeds 120 seconds is counted as killed. A
survivor is a mutant the suite did not kill. It may be equivalent or the
suite may be too weak, and this data does not separate the two. None of
the 72 had a fingerprint match.

Limits: the full 1,645 hashie mutants were not run (400 sampled). No suite was
run for saboteur or lobsters, so those rows are static counts only; the
lobsters suite needs a database and services not provisioned here. For lobsters, 12 mutated files failed to
compile while their originals compiled (`mutated_compile_failed`; a spot check
shows builtin edits such as `statement_removal` and `body_nil` breaking
syntax inside multi-line expressions). They are counted as no match. The
cause was not traced to the engine's own re-parse check, and the 12 are not a
Ruby-version effect on the originals. Subject and parse accounting per workload is in
`results.json`.

## Reproduce

Inputs (all public):

| Workload | Revision |
|---|---|
| hashie | `9c81e8340d6b69940e14d8411f34a3efd7a6aa24` (github.com/hashie/hashie) |
| lobsters | `0d162b9cb010b5e3a54e2b3bfd3e80460254856d` (github.com/lobsters/lobsters) |
| saboteur (workload and mutation generator) | `09b64bb4fb044f87cb0d4a867e5b49b0257e3a11` |

Per-file SHA-256 of every file measured, the exact command line, the Ruby,
Prism and test-tool versions, and the parse and subject accounting are in
`results.json` under `provenance`. The 400 sampled hashie mutants, with their
stable mutation digests and killed or survived outcome, are in
`hashie_sample_outcomes.jsonl`.

```
ruby measure.rb --project DIR --files 'lib/**/*.rb' --out out.json
ruby measure.rb --project DIR --files 'lib/**/*.rb' \
  --suite 'rspec -I lib spec --fail-fast -f progress' --run-all --sample 400 --seed 1 \
  --outcomes outcomes.jsonl --out out.json
rspec spec    # 18 examples, includes clean-process runs of the library and measure.rb
```

The lobsters and saboteur rows are static (no bundle was installed for them; lobsters pins its
gems in its own `Gemfile.lock` at the revision above). The hashie suite ran with `rspec -I lib spec` after installing rspec,
rspec-pending_for and pry (activesupport was not installed); hashie ships no lockfile, so
dependency versions are the ones recorded under `suite_tool` in `results.json`.
`--suite` rewrites project files during the run and restores them after each
mutant, so point `--project` at a scratch copy.
