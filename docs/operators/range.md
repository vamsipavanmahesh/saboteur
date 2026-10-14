# range

Swaps `..` and `...` on bounded ranges. Beginless and endless ranges are left alone: without an upper endpoint, endpoint inclusion has no useful different value. Uses byte edits and the normal parse, arid, suppression and candidate-cap checks.

Runs by default. Use `--operators range` to select it alone, or `--exclude-operators range` to leave it out. An upper-bound test should kill the mutant; merely testing an interior value can leave a real boundary gap. Runtime-defined custom range endpoints may introduce equivalent cases, so review survivors rather than assuming a bug.

Inspired by mutineer's extra mutation operators (github.com/davidteren/mutineer, MIT, by David Teren).

Committed fixture evidence: `ranges` adds two range candidates, one killed by an upper-bound assertion and one survivor where only an interior value is checked. This survivor is a real missing-boundary check, not claimed equivalent.
