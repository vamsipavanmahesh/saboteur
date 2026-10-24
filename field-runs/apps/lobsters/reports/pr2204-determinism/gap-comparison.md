# Determinism gap-field comparison (PR #2204, 3 serial runs)

User protocol: diff ids, statuses, killedBy and gap.

- Stryker report.json mutant schema (enumerated keys): coveredBy, duration, executed, id, killedBy, location, mutatorName, replacement, static, status, statusReason, subject, valueDiffered. NO "gap" field exists in the machine report - recorded as NOT AVAILABLE per schema (not invented).
- Gap classification exists in saboteur's reporter (lib/saboteur/reporter/survivor_classification.rb; kinds incl. boundary/input_gap/assertion_gap/unchecked) and surfaces in the TEXT report survivor block: "app/models/story.rb:777 Story#is_gone? [boundary · #1 of 1 block]".
- Text-report gap label comparison across the 3 runs: all 3 logs carry the identical survivor block: 3 survivors at story.rb:777, label [boundary · #1 of 1 block], same 3 digests (56ec2857eb8103bd comparison, 695982748e0e8ebb + 9786b8df27eddc21 literal_number), identical hint text. Gap labels: IDENTICAL across runs (0 diffs).
- Null/missing consistency: survivors' statusReason and valueDiffered are null in all 3 runs' report.json (compared as equal nulls, not omitted).
