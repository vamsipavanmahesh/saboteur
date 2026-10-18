# Rails monorepos, sub-gems and the custom map

Two layout problems hit saboteur on anything bigger than a single `lib/`:
the changed file sits outside the mutation include, and the spec does not
sit at the conventional mirror path. Both produce refusals or silent
fallbacks that look like "nothing to do". This guide shows both, with real
output, and what actually fixes each in 0.7.0. The setup flow it continues
is in [Saboteur in CI on a pull request](ci-pull-request.md).

## 1. Symptom: the diff changed a file, saboteur says it did not

Real output from a PR branch that changed exactly one source file,
`app/models/sidebars/authors_sidebar.rb`, on a stock Rails app:

```
$ bundle exec saboteur pr origin/master
saboteur: no changed source file lies inside the include scope, so nothing ran. Changed source files outside it: app/models/sidebars/authors_sidebar.rb. Extend include to cover them, or re-run the same command with one --test per existing spec path.
```

The refusal is about the *include*: the default mutation scope is
`lib/**/*.rb`, so a changed file under `app/` - or under
`engines/billing/lib/` in a monorepo, or `kaminari-activerecord/lib/` in a
sub-gem layout (#483) - is invisible to the diff scope. The run stops
rather than falling back to the whole suite: with zero subjects in scope
that fallback was the slowest possible way to learn nothing, and its old
message read as if the diff had touched no source at all.

### Fix: include the tree you actually mutate

```ruby
# config/saboteur.rb
Saboteur.configure do |c|
  c.include = ["app/**/*.rb", "lib/**/*.rb"]
end
```

On a monorepo, name every gem or engine root:

```ruby
c.include = ["app/**/*.rb", "lib/**/*.rb",
             "gems/*/lib/**/*.rb", "engines/*/app/**/*.rb", "engines/*/lib/**/*.rb"]
```

Commit the file so CI and local runs agree. After the fix the same preset
sees the change:

```
saboteur 0.7.0: 2 subjects, 12 mutants, wall 9.97 s, seed 1 (repeat with --seed 1)
```

## 2. Symptom: the spec does not mirror the source path

With the include fixed, the next refusal on a real app is spec naming:

```
saboteur: no spec found for app/models/sidebars/authors_sidebar.rb (expected spec/models/sidebars/authors_sidebar_spec.rb), so nothing ran. Re-run the same command with --test followed by your existing spec paths, or append --all to use the whole suite without changing the source scope.
```

The conventional guess is `spec/<same relative path>_spec.rb`. Apps that
flatten (`spec/models/authors_sidebar_spec.rb`), namespace (`spec/unit/`,
`spec/acceptance/`), or colocate specs inside sub-gems miss it. The ways
out, all honored today:

- `--test spec/models/authors_sidebar_spec.rb` on the command line (repeat
  the flag per spec). Right for a first run and for CI, where the command
  is written once in the workflow file.
- `--all` (config `c.test_selection = :all`) runs the whole configured
  suite against the diff's subjects. Slower per run, zero mapping work.
- Do nothing and let the coverage map take over: after one mapped run,
  specs are chosen by recorded coverage, not by name. The map is built on
  the first run that gets past this refusal.

## 3. The custom map: what it does in 0.7.0

`config/saboteur_custom_map.rb` defines a `SABOTEUR_CUSTOM_MAP` hash from
source path (exact, glob, or Regexp) to spec paths:

```ruby
SABOTEUR_CUSTOM_MAP = {
  "app/services/tax_sync.rb" => ["spec/services/tax_sync_spec.rb"],
  "app/services/**/*.rb"     => ["spec/services/**/*_spec.rb"],
  %r{\Aapp/jobs/(.*)\.rb\z}  => ['spec/jobs/\1_spec.rb'],
  "app/generated/**/*.rb"    => [], # intentionally untested
}.freeze
```

The file loads before the app boots, so it must be plain Ruby (no Rails
constants, no requires of app code). `saboteur doctor` confirms it loads:

```
Custom map: 1 entries (loaded)
```

Validation is strict and load-time: a non-Hash definition, a spec path
outside the project root, a glob that matches no file, two keys with equal
specificity matching the same source, or app code in the file are all
config errors naming the line. Keys that match nothing are warned about as
stale.

One honest limit, verified against the 0.7.0 sources: the map is loaded,
validated, shown in doctor and checked for stale keys, but diff-mode spec
*selection* does not consult it yet - the conventional guess (plus
`--test`, `--all` and the coverage map) decides which specs run. If you
wrote a map expecting it to fix a "no spec found" refusal, use `--test` or
`--all` for now. Track #488 for the error-message side of this.

## 4. Checklist for a monorepo PR check

1. `c.include` covers every tree the PR may touch (`gems/*/lib`, engine
   roots), committed to the repo.
2. The CI ref fetch is deep enough to find the merge base
   (`fetch-depth: 0` on GitHub Actions).
3. Specs resolve: conventional paths, explicit `--test` flags in the
   workflow, or `--all`. Verify once locally with
   `bundle exec saboteur pr origin/main --dry-run`.
4. The budget fits the suite: the `pr` preset's ten minutes bounds the
   whole run; a suite whose baseline alone exceeds it stops early with
   partial evidence (exit 4 unless `--max-duration-ok`).
5. `bundle exec saboteur doctor` is green on the app's CI image, including
   the custom-map line if you keep one.
