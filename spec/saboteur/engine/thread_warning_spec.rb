# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Engine, "threads alive at fork time" do
  let(:err) { StringIO.new }
  let(:engine) { described_class.new(Saboteur::Config.new, err: err) }

  def warnings
    engine.instance_variable_get(:@diagnostics).warnings
  end

  it "names each thread alive at fork time" do
    named = Thread.new { sleep }
    named.name = "pool-reaper"
    engine.send(:warn_about_threads)
    expect(warnings.last).to include("other thread(s) alive at fork time", "pool-reaper")
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
    engine.send(:warn_about_threads)
    expect(warnings.last).to include("thread_warning_spec.rb")
  ensure
    unnamed.kill
    unnamed.join
  end

  it "names a thread with neither name nor backtrace as unknown" do
    ghost = instance_double(Thread, name: nil, backtrace: nil)
    allow(Thread).to receive(:list).and_return([Thread.current, ghost])
    engine.send(:warn_about_threads)
    expect(warnings.last).to include("unknown")
  end

  it "prefers the backtrace frame over unknown when the thread has no name" do
    ghost = instance_double(Thread, name: nil, backtrace: ["app/pool.rb:12:in 'reap'"])
    allow(Thread).to receive(:list).and_return([Thread.current, ghost])
    engine.send(:warn_about_threads)
    expect(warnings.last).to include("app/pool.rb:12")
    expect(warnings.last).not_to include("unknown")
  end

  it "separates several thread names with a comma" do
    first = Thread.new { sleep }
    first.name = "reaper-a"
    second = Thread.new { sleep }
    second.name = "reaper-b"
    engine.send(:warn_about_threads)
    expect(warnings.last).to include("reaper-a, reaper-b").or include("reaper-b, reaper-a")
  ensure
    first.kill
    first.join
    second.kill
    second.join
  end

  it "says nothing when no other thread is alive" do
    allow(Thread).to receive(:list).and_return([Thread.current])
    engine.send(:warn_about_threads)
    expect(warnings).to be_empty
  end
end
