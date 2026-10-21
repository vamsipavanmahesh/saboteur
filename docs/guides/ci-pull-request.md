# Using saboteur in CI on a pull request

A real pull-request check, run end to end against [publify](https://github.com/publify/publify),
a public Rails 7.2 app with RSpec and sqlite. Every output block is copied
from that session. The branch under test adds one method and one spec to
`AuthorsSidebar`, the diff a reviewer would actually open.

The same flow on your own machine is covered by
[Your first 10 minutes on a Rails app](first-10-minutes-rails.md); this guide
is about making it a CI job and reading what the job says.

## 1. The job

The whole job is one command. The `pr` preset bundles the pull-request
defaults: changed methods only, one baseline pass, a ten-minute wall-clock
budget. A budget stop exits 4 and reports partial evidence.

```yaml
# .github/workflows/saboteur.yml (the hand-written version; the Action below is shorter)
on: pull_request
jobs:
  saboteur:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0        # the --since diff needs the merge base
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - run: cp config/database.yml.sqlite config/database.yml
      - run: RAILS_ENV=test bundle exec rails db:schema:load
      - run: bundle exec saboteur pr origin/${{ github.base_ref }}
```

`fetch-depth: 0` matters: an unknown ref exits 2 and a missing merge base
exits 3 rather than silently mutating the whole project.

## 2. Two one-time fixes on a Rails tree

The first run on a stock Rails app refuses - twice, for two different
reasons. Both fixes are one file each.

```
$ bundle exec saboteur pr origin/master
saboteur: no changed source file lies inside the include scope, so nothing ran. Changed source files outside it: app/models/sidebars/authors_sidebar.rb. Extend include to cover them, or re-run the same command with one --test per existing spec path.
```

The default mutation scope is `lib/**/*.rb`, so an app whose code lives in
`app/` produces an empty diff scope, and the run says so instead of
silently running the whole suite against zero subjects. Tell saboteur
about the Rails tree:

```ruby
# config/saboteur.rb
Saboteur.configure do |c|
  c.include = ["app/**/*.rb", "lib/**/*.rb"]
end
```

Second run:

```
saboteur: no spec found for app/models/sidebars/authors_sidebar.rb (expected spec/models/sidebars/authors_sidebar_spec.rb), so nothing ran. Re-run the same command with --test followed by your existing spec paths, or append --all to use the whole suite without changing the source scope.
```

publify keeps the spec at `spec/models/authors_sidebar_spec.rb`, not the
conventional mirror path, and the run refuses to guess. For a one-off,
`--test spec/models/authors_sidebar_spec.rb` on the command line works. The
durable fixes are `--all` (the whole configured suite against the
diff's subjects) or simply letting the coverage map take over:
after the first mapped run, specs are chosen by recorded coverage, not by
name. Commit `config/saboteur.rb` (and the map if you write one) so CI and
local runs agree.

## 3. A real PR run

```sh
bundle exec saboteur pr origin/master --test spec/models/authors_sidebar_spec.rb
```

```
saboteur: preset 'pr': --baseline-passes 1 --max-duration 10m --since origin/master (explicit flags override)
...
saboteur 0.7.0: 2 subjects, 12 mutants, wall 9.97 s, seed 1 (repeat with --seed 1)
killed 8  survived 4  timeout 0  resource limit 0  error 0  skipped 0
score 66.7 %
```

Exit code 1: survivors. Only the changed methods were mutated - 12 mutants
over 2 subjects, ten seconds wall clock, not the whole app.

## 4. What the job is telling you

```
Survivors (4):

app/models/sidebars/authors_sidebar.rb
  AuthorsSidebar#enough_authors?
    app/models/sidebars/authors_sidebar.rb:15 in AuthorsSidebar#enough_authors?
      15: authors.size >= count_threshold
      changed line: app/models/sidebars/authors_sidebar.rb:15
      1 test covered this line and still passed (the missing check may belong in one of them):
        ./spec/models/authors_sidebar_spec.rb[1:2:3]
      - body_true authors.size >= count_threshold -> true 0f5efe2878b091c3
        hint: try asserting this method's result or its effect
      - comparison >= -> == 6ce4cca2711d005e
        hint: try an example at the boundary: equal values, or values one apart
```

Each survivor marks the exact diff line it escaped through (`changed line`),
the covering test that let it live, and a hint for the missing assertion.
The branch's test only checks the happy case with exactly two authors, so
replacing the predicate with `true`, or `>=` with `==`, goes unnoticed.
[How to read survivors](reading-survivors.md) covers the full anatomy.

## 5. Choosing how loud the job is

- **Gate on survivors (default):** exit 1 fails the job, as above.
- **Gate on a score:** `--threshold 80` (or `c.threshold`) fails the run when
  the diff's score drops below the floor.
- **Advisory:** keep the job green and read the report - the
  [GitHub Action](../github-action.md) is advisory by default and posts the
  survivors on the PR, and can [fail on new
  survivors](../github-action.md#failing-on-new-survivors-with-a-baseline)
  when you are ready to enforce.
- **Budget stops fail by default:** a run cut off at ten minutes exits 4
  and prints `partial: X of Y mutants not run` (or says the count is unknown
  if planning did not finish). Pass `--max-duration-ok` explicitly to use
  the ordinary verdict instead; the warning and other failure gates stay.

Either way the JSON and HTML reports land in `.saboteur/` on the runner;
upload them as artifacts or let the Action publish them. Cache `.saboteur/`
between runs so the coverage map and `--incremental` verdicts survive - the
[Action's caching](../github-action.md#caching) does this for you.

## 6. Closing the loop from the PR

The run prints the replay command for each survivor, with the preset's
settings baked in:

```sh
bundle exec saboteur run --id 0f5efe2878b091c3 --since origin/master \
  --test spec/models/authors_sidebar_spec.rb \
  --baseline-passes 1 --max-duration 600.0 --seed 1
```

Add the missing boundary test, push, and the next CI run goes green. The
full kill-one-survivor loop, with output, is in
[Your first 10 minutes on a Rails app](first-10-minutes-rails.md).
