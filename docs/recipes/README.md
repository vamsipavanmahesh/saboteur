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

## factory_bot and other factories

Factory definitions load once in the parent and every child inherits them, so
there is nothing to configure. Two habits matter:

- Build records inside examples (`create(:user)` in an `it` or `let`), not at
  load time. A record created when the spec file loads is created in the
  parent, before the fork, and every child sees the same row.
- Sequences start from the parent's state in every child, so a mutant never
  sees numbers another mutant used. Do not assert on absolute sequence values
  that depend on how many examples ran before; the first test to touch a
  sequence in each child decides them.

`FactoryBot.lint` is slow and runs the whole factory set. Keep it in its own
spec or a CI step, not in a `before(:suite)` that every saboteur baseline pass
also runs, unless you want that time in every run.

## Rails fixtures and transactional tests

Fixtures load into the test database before mutants run. Transactional
examples roll back inside the child that ran them, so one mutant's writes do
not reach the next. With `jobs` above 1 each worker has its own copy of the
database (see the Rails section of the README), so workers do not see each
other's rows either.

A change to a fixture file changes the cache keys, so `--incremental` does not
reuse verdicts after you edit one.

## DatabaseCleaner

With `jobs: 1` the child writes to your real test database. A cleaning
strategy that truncates tables (`:truncation`) is safe there only because it
is a test database; never point saboteur at a development database. With
`jobs` above 1 each worker truncates its own copy.

Run the cleaner per example, as usual (`before(:each)` / `after(:each)`), not
once at load time in the parent: a load-time clean runs once and the children
inherit a database it already emptied.

## Capybara and system specs

A browser, a driver or an app server started in the parent is shared by every
child, which breaks the one rule above. Start them per example (or per child
in `after_fork`), and stop them in the same place. Prefer a rack-test driver
for the specs you want mutation-tested; a browser makes each mutant slow, and
a mutant that hangs the page loses its time to the timeout.

## ActionMailer and ActiveJob

The test delivery method (`config.action_mailer.delivery_method = :test`) and
the test queue adapter (`config.active_job.queue_adapter = :test`) keep their
state in the process, so each child starts clean. Nothing to configure. A
real queue adapter that talks to Redis falls under the Sidekiq recipe: close
the connection in `before_fork`.

## Tests that start saboteur

A test that runs saboteur (an integration test of a tool built on it, for
example) will refuse to start inside a mutant child, by design. Stub the run
in such tests; see docs/design.md 6.3.
