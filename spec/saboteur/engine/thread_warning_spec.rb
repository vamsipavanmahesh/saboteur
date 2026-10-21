# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine, "threads alive at fork time" do
  before do
    # This nested engine has a fake boot, not ownership of the outer run's Coverage.
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return([{}, {}])
  end

  let(:err) { StringIO.new }
  let(:engine) { described_class.new(Saboteur::Config.new, err: err) }

  def warnings
    engine.instance_variable_get(:@diagnostics).warnings
  end

  it "appends no caveat when every alive thread is a known one" do
    reaper = instance_double(Thread, name: "AR Pool Reaper", backtrace: ["pool.rb:1"])
    allow(Thread).to receive(:list).and_return([Thread.current, reaper])
    Saboteur::Engine::ThreadWarnings.warn(engine.instance_variable_get(:@diagnostics))
    expect(warnings.last).to include("AR Pool Reaper")
    expect(warnings.last).not_to include("left behind")
  end

  it "says nothing about the pool reaper in rails mode (#1229)" do
    reaper = instance_double(Thread, name: "AR Pool Reaper", backtrace: ["pool.rb:1"])
    allow(Thread).to receive(:list).and_return([Thread.current, reaper])
    Saboteur::Engine::ThreadWarnings.warn(engine.instance_variable_get(:@diagnostics), rails: true)
    expect(warnings).to be_empty
  end

  it "passes the rails setting from the run's config to the thread warning (#1229)" do
    reaper = instance_double(Thread, name: "AR Pool Reaper", backtrace: ["pool.rb:1"])
    allow(Thread).to receive(:list).and_return([Thread.current, reaper])
    map = instance_double(Saboteur::Selection::CoverageMap, tests: [])
    rails_engine = described_class.new(Saboteur::Config.new({ "rails" => true }), err: err)
    rails_engine.send(:inform_about_run, [], map)
    expect(rails_engine.instance_variable_get(:@diagnostics).warnings).to be_empty

    plain = described_class.new(Saboteur::Config.new, err: err)
    plain.send(:inform_about_run, [], map)
    expect(plain.instance_variable_get(:@diagnostics).warnings.last).to include("AR Pool Reaper")
  end

  it "still warns about every other thread in rails mode" do
    reaper = instance_double(Thread, name: "AR Pool Reaper", backtrace: ["pool.rb:1"])
    other = instance_double(Thread, name: "flusher", backtrace: ["flush.rb:2"])
    allow(Thread).to receive(:list).and_return([Thread.current, reaper, other])
    Saboteur::Engine::ThreadWarnings.warn(engine.instance_variable_get(:@diagnostics), rails: true)
    expect(warnings.last).to start_with("1 other thread(s) alive at fork time; they do not run in children: flusher")
    expect(warnings.last).not_to include("AR Pool Reaper")
  end

  it "keeps the reaper warning outside rails mode" do
    reaper = instance_double(Thread, name: "AR Pool Reaper", backtrace: ["pool.rb:1"])
    allow(Thread).to receive(:list).and_return([Thread.current, reaper])
    Saboteur::Engine::ThreadWarnings.warn(engine.instance_variable_get(:@diagnostics), rails: false)
    expect(warnings.last).to include("AR Pool Reaper")
  end

  it "words the whole warning: count, each thread with its explanation, and the left-behind caveat" do
    reaper = instance_double(Thread, name: "AR Pool Reaper", backtrace: ["pool.rb:1"])
    other = instance_double(Thread, name: "flusher", backtrace: ["flush.rb:2"])
    allow(Thread).to receive(:list).and_return([Thread.current, reaper, other])
    Saboteur::Engine::ThreadWarnings.warn(engine.instance_variable_get(:@diagnostics))
    explanation = Saboteur::Engine::ThreadWarnings::KNOWN_FORK_THREADS.fetch("AR Pool Reaper")
    expect(warnings.last).to eq(
      "2 other thread(s) alive at fork time; they do not run in children: AR Pool Reaper (#{explanation}), " \
      "flusher; a thread that does not run in a child cannot do background work a mutant's test may " \
      "rely on (a pool reaper, a flusher), so results can differ when one is left behind"
    )
  end

  it "names an unnamed thread by the first frame of its backtrace" do
    thread = Thread.new { sleep }
    Thread.pass until thread.backtrace&.any?
    first = thread.backtrace.first
    last = thread.backtrace.last
    Saboteur::Engine::ThreadWarnings.warn(engine.instance_variable_get(:@diagnostics))
    expect(warnings.last).to include(first)
    expect(warnings.last).not_to include(last) unless last == first
  ensure
    thread.kill
    thread.join
  end

  it "names each thread alive at fork time" do
    named = Thread.new { sleep }
    named.name = "pool-reaper"
    Saboteur::Engine::ThreadWarnings.warn(engine.instance_variable_get(:@diagnostics))
    expect(warnings.last).to include("other thread(s) alive at fork time", "pool-reaper")
  ensure
    named.kill
    named.join
  end

  it "explains ActiveRecord's pool reaper as harmless" do
    named = Thread.new { sleep }
    named.name = "AR Pool Reaper"
    Saboteur::Engine::ThreadWarnings.warn(engine.instance_variable_get(:@diagnostics))
    expect(warnings.last).to include("AR Pool Reaper", "expected harmless", "reconnect")
  ensure
    named.kill
    named.join
  end

  it "describes the debug gem's server thread per fork mode and names the off switch" do
    named = Thread.new { sleep }
    named.name = "DEBUGGER__::SESSION@server"
    Saboteur::Engine::ThreadWarnings.warn(engine.instance_variable_get(:@diagnostics))
    expect(warnings.last).to include("DEBUGGER__::SESSION@server", "RUBY_DEBUG_FORK_MODE",
                                     "with parent no debugger runs in children",
                                     "interfere with supervised mutation runs",
                                     "unattended", "RUBY_DEBUG_OPEN")
    expect(warnings.last).not_to include("not expected to affect results")
  ensure
    named.kill
    named.join
  end

  it "says what an unknown thread can break" do
    named = Thread.new { sleep }
    named.name = "my-sdk-flusher"
    Saboteur::Engine::ThreadWarnings.warn(engine.instance_variable_get(:@diagnostics))
    expect(warnings.last).to include("my-sdk-flusher", "background work")
  ensure
    named.kill
    named.join
  end

  it "falls back to the first backtrace frame for an unnamed thread" do
    ready = Queue.new
    unnamed = Thread.new do
      ready << true
      sleep
    end
    ready.pop
    Saboteur::Engine::ThreadWarnings.warn(engine.instance_variable_get(:@diagnostics))
    expect(warnings.last).to include("thread_warning_spec.rb")
  ensure
    unnamed.kill
    unnamed.join
  end

  it "names a thread with neither name nor backtrace as unknown" do
    ghost = instance_double(Thread, name: nil, backtrace: nil)
    allow(Thread).to receive(:list).and_return([Thread.current, ghost])
    Saboteur::Engine::ThreadWarnings.warn(engine.instance_variable_get(:@diagnostics))
    expect(warnings.last).to include("unknown")
  end

  it "prefers the backtrace frame over unknown when the thread has no name" do
    ghost = instance_double(Thread, name: nil, backtrace: ["app/pool.rb:12:in 'reap'"])
    allow(Thread).to receive(:list).and_return([Thread.current, ghost])
    Saboteur::Engine::ThreadWarnings.warn(engine.instance_variable_get(:@diagnostics))
    expect(warnings.last).to include("app/pool.rb:12")
    expect(warnings.last).not_to include("unknown")
  end

  it "separates several thread names with a comma" do
    first = Thread.new { sleep }
    first.name = "reaper-a"
    second = Thread.new { sleep }
    second.name = "reaper-b"
    Saboteur::Engine::ThreadWarnings.warn(engine.instance_variable_get(:@diagnostics))
    expect(warnings.last).to include("reaper-a, reaper-b").or include("reaper-b, reaper-a")
  ensure
    first.kill
    first.join
    second.kill
    second.join
  end

  it "says nothing when no other thread is alive" do
    allow(Thread).to receive(:list).and_return([Thread.current])
    Saboteur::Engine::ThreadWarnings.warn(engine.instance_variable_get(:@diagnostics))
    expect(warnings).to be_empty
  end
end
