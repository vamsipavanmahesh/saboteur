# Accepting a survivor

A survivor is a mutant the suite did not kill. For each one, decide: kill it
with a test (the usual answer), fix the code (the mutant showed a real
smell), or accept it. Accepting means recording WHY the survivor is fine, in
a form every later run checks. There are three ways to accept a survivor;
the ignore file is the primary story, the other two are advanced paths.

## Primary: the ignore file

`config/saboteur_ignore.rb` holds one entry per accepted survivor:

```ruby
Saboteur.ignore do |i|
  i.mutation "698e4b7eca600583",
             subject: "Cart#total",
             reason: "equivalent: .first and .last pick the same element of the one-element array",
             state: "accepted_equivalent"
end
```

Why this is the default:

- **One reviewed file.** Acceptance goes through code review like any other
  change, in one place.
- **Digests bind the exact mutant.** Edit the line and the digest changes,
  so the entry stops matching instead of silently blessing new code.
- **Stale entries are flagged.** When an entry no longer matches any mutant,
  the run warns: `stale ignore entry <subject> <digest>: no such mutation`.

States: `accepted_equivalent` (the default - you proved the change
unobservable) and `wont_fix` (reviewed, deliberately not fixed) suppress the
survivor's exit failure; the survivor still counts in the score. `todo`
records the decision to fix and lets the survivor keep counting as a
survivor.

Reason style: write what you verified and how ("hand-applied the swap; the
printed note is byte-identical"), not what you hope is true.

## Advanced: inline suppression

`# saboteur:disable-line [operator ...] reason="..."` on the mutated line
suppresses matching mutants at that line. Directives are parsed from real
comments only, never from strings; one nonblank `reason="..."` is required,
and operators must be registry names. Directives also join the subject's
incremental-run signature, so adding or editing one re-runs that subject
under `--incremental` instead of reusing cached verdicts. An ignore entry
keeps matching a suppressed mutant by digest; the two mechanisms layer.
Use this for a one-line point fix, when the reason reads best next to the
code.

## Advanced: baseline propose/accept

For adopting a whole existing tree at once (legacy bootstrap),
`saboteur baseline propose --baseline PATH --proposal PATH` runs the suite,
captures the current survivor set into an editable proposal, and
`saboteur baseline accept` moves the reviewed proposal to the destination.
Proposing needs a fresh whole or subject scope run - baseline refuses
`--since`/`--incremental` and `--threshold` runs - and the run must be
proposable: hard blockers refuse the proposal (each blocker is named),
while soft gaps are tolerated and listed in the result. `propose` prints a
terminal summary by default; `--format json` emits the JSON payload.
`--previous SHA256` on propose/accept is a replacement guard: it pins the
destination hash you reviewed, so accept fails instead of overwriting a
baseline someone else changed.

## Which one

- A few survivors in ongoing work: the ignore file.
- One line whose reason belongs next to the code: an inline directive.
- First adoption on a tree with many survivors: baseline propose/accept.
