# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Selection::Recorder do
  it "records files under their canonical path" do
    Dir.mktmpdir do |dir|
      real = File.join(dir, "real.rb")
      link = File.join(dir, "link.rb")
      File.write(real, "")
      File.symlink(real, link)
      recorder = described_class.new([link])
      expect(recorder.instance_variable_get(:@files)).to eq(Set.new([File.realpath(real)]))
    end
  end

  it "carries the child-loaded sources and the build time into the built map (#353)" do
    map = described_class.new([]).result(build_seconds: 0.1, loaded_files: ["/app/support/helper.rb"])
    expect(map.loaded_files).to eq(["/app/support/helper.rb"])
    expect(map.build_seconds).to eq(0.1)
  end

  # The tracer sees every Ruby call in the process while enabled, including
  # calls from another thread or a trap handler. Nothing in the recorder's
  # path may take a lock (an rspec-mocks stub does, and raises ThreadError in
  # a trap handler), so these two specs use the real canonicalizer (#807).
  it "treats a path the canonicalizer refuses as unwanted instead of raising into the program" do
    wanted = described_class.new([__FILE__]).instance_variable_get(:@calls).instance_variable_get(:@wanted)
    expect(wanted["a\0b"]).to be(false)
    expect(wanted[__FILE__]).to be(true)
  end

  it "records a call made from a trap handler while the tracer is enabled" do
    calls = described_class.new([__FILE__]).instance_variable_get(:@calls)
    target = Class.new { def zz = 1 }.new
    handled = false
    previous = Signal.trap("USR1") do
      target.zz
      handled = true
    end
    calls.enable
    Process.kill("USR1", Process.pid)
    sleep 0.01 until handled
    calls.pause
    expect(calls.drain.fetch(File.realpath(__FILE__)).map(&:last)).to eq([:zz])
  ensure
    calls&.pause
    Signal.trap("USR1", previous) if previous
  end
end
