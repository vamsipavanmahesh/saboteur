# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine, "threads alive at fork time" do
  before do
    # This nested engine has a fake boot, not ownership of the outer run's Coverage.
    allow_any_instance_of(Saboteur::Engine).to receive(:suspend_coverage).and_return({})
  end

  let(:err) { StringIO.new }
  let(:engine) { described_class.new(Saboteur::Config.new, err: err) }

  def warnings
    engine.instance_variable_get(:@diagnostics).warnings
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

  it "explains the debug gem's server thread as harmless and names the off switch" do
    named = Thread.new { sleep }
    named.name = "DEBUGGER__::SESSION@server"
    Saboteur::Engine::ThreadWarnings.warn(engine.instance_variable_get(:@diagnostics))
    expect(warnings.last).to include("DEBUGGER__::SESSION@server", "not expected to affect results",
                                     "RUBY_DEBUG_FORK_MODE", "RUBY_DEBUG_OPEN")
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
