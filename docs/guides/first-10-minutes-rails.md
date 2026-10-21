# Your first 10 minutes with saboteur on a Rails app

A real first session, run end to end against [publify](https://github.com/publify/publify),
a public Rails 7.2 blog app with RSpec and sqlite. Every output block below is
copied from that session, trimmed only for width. Rails 7.2 on Ruby 3.4,
saboteur 0.7.0, Linux.

The plan: install, preview the cost, run one small class, read the one
survivor, kill it with a test, and rerun to a clean exit.

## 1. Install (1 minute)

```sh
git clone https://github.com/publify/publify.git && cd publify
cp config/database.yml.sqlite config/database.yml
bundle install
RAILS_ENV=test bundle exec rails db:schema:load
bundle add saboteur --group development,test
```

```
Fetching saboteur 0.7.0
Installing saboteur 0.7.0
```

Nothing else changes. saboteur runs your existing spec suite; there is no
config file to write for a first run.

## 2. Preview the cost (30 seconds)

```sh
bundle exec saboteur run --dry-run
```

```
lib/publify_plugins/gravatar.rb:27 PublifyPlugins::Gravatar.gravatar_tag  38 mutants
...
Total: 395 mutants; 56 dropped by max_mutants_per_method
no estimate: run once to build the coverage map
```

`--dry-run` boots nothing and runs no tests: it lists every subject and the
mutant count, so you can pick a small first scope instead of mutating 395
mutants on your first try. If you fat-finger a flag here you meet exit code 2
(usage error) - cheap, before any suite runs:

```
$ saboteur run --subjects ...
invalid option: --subjects
Did you mean?  subject
```

## 3. Run one small class (2 minutes)

Pick a class with a spec you know passes, and name both the source and the
spec. saboteur refuses to guess when it cannot pair them itself:

```
$ bundle exec saboteur run --subject 'PublifyPlugins::AvatarPlugin'
saboteur: no spec found for lib/publify_plugins/avatar_plugin.rb (expected spec/publify_plugins/avatar_plugin_spec.rb), so nothing ran. Re-run the same command with --test followed by your existing spec paths...
```

Naming both sides explicitly always works:

```sh
bundle exec saboteur run app/models/sidebars/authors_sidebar.rb --test spec/models/authors_sidebar_spec.rb
```

```
saboteur: checking the unchanged suite twice (seed 1)
saboteur: building coverage map (runs the selected specs once)
...
saboteur 0.7.0: 1 subjects, 6 mutants, wall 6.81 s, seed 1 (repeat with --seed 1)
killed 5  survived 1  timeout 0  resource limit 0  error 0  skipped 0
score 83.3 %
```

The exit code is 1: one survivor. Two things happened before any mutant ran:
the unchanged suite was executed twice (a flaky suite stops the run here,
not after an hour of mutants), and a coverage map picked exactly the specs
that touch this class. If your suite is red at this point, that is the real
bug to fix first - saboteur will not mutate against a failing baseline.

## 4. Read the survivor (2 minutes)

```
Survivors (1):

app/models/sidebars/authors_sidebar.rb
  AuthorsSidebar#authors
    app/models/sidebars/authors_sidebar.rb:11 in AuthorsSidebar#authors
      11: @authors = User.where(state: "active").order(:name)
      1 test covered this line and still passed (the missing check may belong in one of them):
        ./spec/models/authors_sidebar_spec.rb[1:2:1]
      - chain_removal .where(state: "active") ->  23260e9639c7a675
        hint: try the shorter chain's value against the longer one; ...
```

Read it as a sentence: deleting `.where(state: "active")` still passes the
suite, so no test ever checks that inactive users stay out of the sidebar.
The hint is a suggestion, not a diagnosis - a survivor can also be an
equivalent mutant. This one is a genuine gap.

## 5. Kill it with a test (2 minutes)

```ruby
it "leaves out inactive users" do
  inactive = create(:user, state: "closed")
  expect(sidebar.authors).not_to include(inactive)
end
```

## 6. Replay the exact mutant (1 minute)

The run's Next steps print the replay command with the mutant's digest:

```sh
bundle exec saboteur run --id 23260e9639c7a675 --test spec/models/authors_sidebar_spec.rb \
  --operators '' --exclude-operators '' --seed 1 -- app/models/sidebars/authors_sidebar.rb
```

```
--- a/app/models/sidebars/authors_sidebar.rb
+++ b/app/models/sidebars/authors_sidebar.rb
@@ -10,3 +10,3 @@
   def authors
-    @authors = User.where(state: "active").order(:name)
+    @authors = User.order(:name)
Selected tests:
  ./spec/models/authors_sidebar_spec.rb[1:2:1]
  ./spec/models/authors_sidebar_spec.rb[1:2:2]

Replay: AuthorsSidebar#authors chain_removal 23260e9639c7a675 (killed)
```

The new spec is now in the selected set, and the mutant dies. Exit code 0.

## 7. Rerun clean (1 minute)

```sh
bundle exec saboteur run app/models/sidebars/authors_sidebar.rb --test spec/models/authors_sidebar_spec.rb
```

```
saboteur 0.7.0: 1 subjects, 6 mutants, wall 7.25 s, seed 1 (repeat with --seed 1)
killed 6  survived 0  timeout 0  resource limit 0  error 0  skipped 0
score 100.0 %
```

That is the whole loop: a red-to-green score driven by a test that was
actually missing.

## Where next

- Widen the scope with `--since origin/main` on your own branch; the
  [pull-request guide](../pull-requests.md) covers that workflow.
- The JSON and HTML reports from every run sit in `.saboteur/report.json`
  and `.saboteur/report.html`; [How to read survivors](reading-survivors.md)
  goes deeper on survivor anatomy.
- `--agent` prints one bounded JSON payload instead of the text report, for
  AI coding agents; `saboteur agent-skill` prints the paste-in skill block.
- For CI, including caching the coverage map so reruns stay cheap:
  the [GitHub Action](../github-action.md) guide.
- `bundle exec saboteur help` lists every command, option, config key and
  exit code.
