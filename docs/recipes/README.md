# Recipes

How to run saboteur on suites that use common test tools. Each recipe is a
few lines in a hooks file listed in `config/saboteur.rb`:

```ruby
Saboteur.configure do |c|
  c.hooks = ["spec/saboteur_hooks.rb"]
end
```

Inside a mutant child, `ENV["SABOTEUR_CHILD"]` is set. Use it to change test
behaviour only during a saboteur run.

## The one rule: nothing shared across fork

saboteur loads your app once, then forks a child per mutant. Anything the
parent opened before the fork (database sockets, Redis connections, HTTP
keep-alive connections, file locks) is shared by every child unless you
close it. Close it in `before_fork` or reopen it in `after_fork`.

The Rails profile (`c.rails = true`) already does this for Active Record.

## VCR: never record during a run

A mutant changes what your code sends. If VCR may record, a mutant can write
its broken requests into your cassettes. Replay only:

```ruby
# spec/saboteur_hooks.rb
Saboteur.hook(:after_fork) do
  VCR.configure { |config| config.default_cassette_options = { record: :none } }
end
```

A mutant that makes a request no cassette has will then fail its tests,
which is the right result: it is killed.

## WebMock

Nothing to do. `WebMock.disable_net_connect!` from your spec helper is
loaded in the parent and inherited by every child. If your suite allows
localhost for a server it starts, that server must be started per test (or
per child), not once in the parent.

## Sidekiq

Most suites use `Sidekiq::Testing.fake!` or `inline!`; both work in children
as they are. If your tests talk to a real Redis, close the client's
connections in `before_fork` with your Redis client's documented disconnect
call, so each child opens its own.

## Time helpers (Timecop, ActiveSupport::Testing::TimeHelpers)

They work per process. Do not freeze time in the parent (for example in a
`before(:suite)` that runs at load time): every child would inherit it.

## SimpleCov

saboteur needs Ruby's `Coverage` module for itself. Guard SimpleCov with an
environment variable (`if ENV["COVERAGE"]`) and leave it unset for saboteur
runs.

## Tests that start saboteur

A test that runs saboteur (an integration test of a tool built on it, for
example) will refuse to start inside a mutant child, by design. Stub the run
in such tests; see docs/design.md 6.3.
