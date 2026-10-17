# Rails engines and dummy apps

Engine-style gems keep an embedded Rails app under `spec/dummy` whose specs
load a Rails env (`require "rails_helper"`) the parent process does not have,
and some repos keep env-dependent integration specs under `spec/`. Loading
the whole spec tree then dies at setup. When that happens the error names
the files that failed to load; exclude the broken subtrees in
`config/saboteur.rb`:

```ruby
Saboteur.configure do |c|
  c.rspec_args = ["--exclude-pattern", "spec/dummy/**/*_spec.rb,spec/integration/**/*_spec.rb"]
end
```

For a plain Rails app (no engine), see the README's
[Rails apps](../../README.md#rails-apps) section.
