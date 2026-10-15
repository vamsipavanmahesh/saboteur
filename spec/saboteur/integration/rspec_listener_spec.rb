# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Integration::RSpec::Listener do
  def failed(id, exception)
    result = Struct.new(:exception).new(exception)
    example = Struct.new(:id, :execution_result).new(id, result)
    described_class.new.tap { |listener| listener.example_failed(Struct.new(:example).new(example)) }
  end

  # Text.utf8 is mutable code: a mutant that breaks it must not flip the run
  # to error - the recorded failure is what classifies the kill (CI #272).
  it "falls back to an escaped message when the scrub itself is broken" do
    allow(Saboteur::Text).to receive(:utf8).and_raise(RuntimeError, "mutant")
    expect(failed("t1", RuntimeError.new("boom caf\u00e9")).failure_messages["t1"]).to include("boom")
    allow(Saboteur::Text).to receive(:utf8).and_return(nil)
    expect(failed("t2", RuntimeError.new("kaput")).failure_messages["t2"]).to include("kaput")
  end

  # Exception messages can embed paths whose bytes are invalid under the locale
  # encoding; .lines/.strip on those raises and flips the whole run to error.
  it "scrubs failure messages whose bytes are invalid under the locale encoding" do
    ascii = failed("t1", RuntimeError.new("café \xE9".dup.force_encoding("US-ASCII")))
    utf8 = failed("t2", RuntimeError.new("café \xE9".dup.force_encoding("UTF-8")))
    expect(ascii.failure_messages["t1"]).to eq("café �")
    expect(utf8.failure_messages["t2"]).to eq("café �")
  end

  # A verdict that does not hold up should say why the test failed.
  it "keeps the first line of each failure message, at most 200 characters" do
    listener = failed("t1", RuntimeError.new("\nexpected: 2\n     got: 3"))
    expect(listener.failure_messages).to eq({ "t1" => "expected: 2" })
    expect(failed("t2", RuntimeError.new("x" * 500)).failure_messages["t2"].size).to eq(200)
  end

  # A neutral re-run (the verdict check) needs the whole failure to say why
  # the killer failed with the method unchanged (#296).
  it "keeps the full failure detail: class, message and first frames, capped and scrubbed" do
    error = begin
      raise "expected: 2\n     got: 3"
    rescue RuntimeError => e
      e
    end
    detail = failed("t1", error).failure_details["t1"]
    expect(detail).to include("RuntimeError: expected: 2\n     got: 3")
    expect(detail).to include(__FILE__)
    expect(failed("t2", RuntimeError.new("x" * 5_000)).failure_details["t2"].size).to eq(2_000)
    expect(failed("t3", nil).failure_details["t3"]).to be_nil
  end

  # RSpec's own frames (notify_failure, handle_failure) lead an expectation
  # backtrace; they must not crowd the spec line out of the cap (#296).
  it "drops rspec-internal frames so the detail shows the project frames" do
    error = RuntimeError.new("expected: 0\n     got: 3")
    error.set_backtrace(
      ["/w/vendor/bundle/ruby/3.3.0/gems/rspec-support-3.13.7/lib/rspec/support.rb:110:in `notify_failure'",
       "/w/vendor/bundle/ruby/3.3.0/gems/rspec-expectations-3.13.5/lib/rspec/expectations/handler.rb:37:in `x'",
       "./spec/saboteur/cli_spec.rb:955:in `block (3 levels) in <top (required)>'"]
    )
    detail = failed("t1", error).failure_details["t1"]
    expect(detail).to include("./spec/saboteur/cli_spec.rb:955")
    expect(detail).not_to include("rspec-support")
    expect(detail).not_to include("rspec-expectations")
  end

  # Degenerate case: an error raised inside rspec itself keeps its frames
  # rather than reporting nothing.
  it "keeps the frames when every frame is rspec-internal" do
    error = RuntimeError.new("boom")
    error.set_backtrace(["/gems/rspec-support-3.13.7/lib/rspec/support.rb:110:in `notify_failure'"])
    expect(failed("t1", error).failure_details["t1"]).to include("rspec-support")
  end

  it "records the exception class" do
    expect(failed("t1", NoMethodError.new("m")).failure_classes).to eq({ "t1" => "NoMethodError" })
  end
end
