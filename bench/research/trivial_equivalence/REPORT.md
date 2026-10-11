# Spike: can an instruction-sequence comparison prove Ruby mutants equivalent?

Status: research only. Nothing here is wired into the engine, and no
suppression feature ships from it. Roadmap Milestone 2 asked for a measured
yes or no. This is the measurement.

## Verdict

**No, not as a feature.** The comparison is sound by construction, but it
proved 0 of 9,178 mutants equivalent on three real code bases. A hit rate of 0%
(and so 0 wrong skips) means there is nothing to ship. The roughly 30% of the
original study (Papadakis et al., 2015) does not carry over to saboteur's
operators on CRuby.

Recommendation: do not build compiler-equivalence suppression. Take the one
related idea the data supports, proven pattern checks on the Prism tree (for
example a literal inside a branch that a constant condition removes), as a
separate item, and measure it the same way before shipping.

## What "identical" means here

The harness compiles the whole original file and the whole mutated file with
`RubyVM::InstructionSequence.compile` and compares the results as trees. Whole
files, so nested sequences and every method are covered. The mutant is proven
equivalent only if the trees are equal. Anything else, including a compile
error on either side, is unproven, and an unproven mutant always runs.

| Part of the sequence | Compared? | Why |
|---|---|---|
| Instructions and every operand (literals, constant and method names, call flags, branch targets) | yes | the literal pool lives in the operands; a changed literal differs |
| Nested sequences (blocks, methods, class bodies, rescue and ensure bodies) | yes, recursively | a change inside a block must not hide |
| Catch (exception) table, with its nested sequences | yes | rescue, ensure, retry, break and next live here |
| Local variable table and parameter description | yes | a rename is treated as different, which is conservative |
| Sequence type, label, stack and local sizes | yes | derived, so equal code gives equal values |
| File paths, node ids, code columns | no | tooling metadata only |
| Line numbers | strict level: yes. relaxed level: no | see below |

Two levels:

- **strict** keeps line numbers. A mutant that moves any line differs.
- **relaxed** drops line numbers, and refuses to prove anything for a file
  that contains a reflective call (`caller`, `binding`, `eval`,
  `source_location`, `__LINE__`, `method`, `define_method`, `send`,
  `RubyVM`, `TracePoint`, `set_backtrace` and similar; the full list is in
  `reflection_scan.rb`). The list is a denylist, not a proof. Relaxed mode
  accepts that an ordinary `raise` exposes line numbers through backtraces;
  the wrong-skip count is the check on that.

Known exposure that no instruction comparison can close: error_highlight and
`RubyVM::AbstractSyntaxTree` read the source file, not the instructions;
anything that reads its own source text (`File.read(__FILE__)`) is likewise
outside the comparison. The harness does not claim these are covered.

## Pins

- CRuby 3.3.6 (2024-11-05 revision 75015d4c1f) on x86_64 Linux.
- Compile options exactly as the interpreter reports them, recorded in
  `results.json`: peephole_optimization, specialized_instruction,
  operands_unification, inline_const_cache on; instructions_unification and
  tailcall_optimization off; frozen_string_literal as set by each file's magic
  comment. Other versions or options can compile differently, so a proof is
  valid only for the pinned compiler.
- Mutants come from saboteur's builtin operators at main 09b64bb.

## Results

| Workload | Files | Mutants | Strict proven | Relaxed proven | Relaxed refused for reflection | Wrong skips |
|---|---:|---:|---:|---:|---:|---:|
| hashie `lib/**/*.rb` (41 files) | 41 | 1,645 | 0 | 0 | 1,251 | 0 |
| saboteur `lib/**/*.rb` | 43 | 3,589 | 0 | 0 | 1,368 | 0 |
| lobsters `app/models/*.rb`, `lib/**/*.rb` | 49 | 3,944 | 0 | 0 | 1,684 | 0 |
| **Total** | 133 | **9,178** | **0** | **0** | 4,303 | **0** |

Lobsters: 12 mutants failed to compile (the project targets a newer Ruby than
the pin); they are counted as unproven. Raw data: `results.json`.

What this does and does not show:

- Hit rate is 0 of 9,178 at both levels. The wrong-skip count is 0 because
  nothing was skipped, so it says nothing about soundness on real code. Soundness
  is argued by construction (equal instruction trees run the same code) and
  checked only by the positive controls below.
- Ground truth: on hashie, 400 mutants were drawn at random (seed 1) and run
  against the 719-example suite. 66 survived (16.5%). If that rate held for all
  1,645, about 270 would survive, and the comparison identified none of them as
  equivalent. A survivor is equivalent or undertested, so this is not a count
  of equivalent mutants.
- The full 1,645 were not run, and no suite was run for saboteur or lobsters
  (the lobsters suite needs a database and services not provisioned here). The
  lobsters and saboteur numbers are static hit rates only. With zero proofs
  there was nothing for a suite to contradict.
- The sample ran the hashie suite with `--fail-fast`, in place, one mutant at a
  time.

## Why the hit rate is zero

Saboteur's operators change values and control flow, and the compiler keeps
both. The spec file has positive controls showing the comparison does prove
the shapes the compiler itself removes: a changed branch behind `if true`, and
a changed statement behind a modifier `if false`. It does not prove a changed
statement after `return` (the compiler keeps it). Those shapes did not occur
among the generated mutants.

## Reproduce

```
ruby measure.rb --project DIR --files 'lib/**/*.rb' --out out.json
ruby measure.rb --project DIR --files 'lib/**/*.rb' \
  --suite 'rspec -I lib spec --fail-fast -f progress' --run-all --sample 400 --seed 1 --out out.json
rspec spec          # judge specs, 14 examples
```

Run against a scratch copy: `--suite` rewrites project files during the run and
restores them after each mutant.
