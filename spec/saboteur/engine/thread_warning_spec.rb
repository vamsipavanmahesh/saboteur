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
    unnamed = Thread.new { sleep }
    engine.send(:warn_about_threads)
    expect(warnings.last).to include("thread_warning_spec.rb")
  ensure
    unnamed.kill
    unnamed.join
  end

  it "says nothing when no other thread is alive" do
    Thread.list.reject { |thread| thread == Thread.current }.each(&:kill)
    engine.send(:warn_about_threads)
    expect(warnings).to be_empty
  end
end
