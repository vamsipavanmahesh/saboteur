# macOS Seatbelt sandbox (opt-in)

Landlock is Linux-only, so on macOS mutant children run with no sandbox by
default: the hazard guard and canary are the only protection. `c.sandbox =
"seatbelt"` opts into a Seatbelt profile in each mutant child:

```ruby
Saboteur.configure do |c|
  c.sandbox = "seatbelt" # macOS Seatbelt sandbox (probe-gated, #436)
end
```

A forked probe must first prove a deny-default profile really blocks a write.
A macOS without Seatbelt degrades to the guard and canary with a one-time note; an errored or unenforcing probe refuses the run. It is opt-in because `sandbox_init` is Apple-deprecated with no
published replacement (#436).

| Platform | Sandbox | Protection |
| --- | --- | --- |
| macOS, default | None; Landlock is Linux-only. | Hazard guard + canary. |
| macOS, `c.sandbox = "seatbelt"` | Seatbelt profile in each mutant child, when the probe enforces. | Seatbelt + hazard guard + canary. |

`c.sandbox = true` and `"strict"` keep their Linux meaning; see the
[doctor guide](doctor.md) for how the sandbox status is reported.
