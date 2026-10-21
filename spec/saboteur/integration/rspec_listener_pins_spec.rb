# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Integration::RSpec::Listener, "pins" do
  def notification(id, exception: nil, rerun: "./spec/a_spec.rb")
    result = Struct.new(:exception).new(exception)
    example = Struct.new(:id, :execution_result, :metadata).new(id, result, { rerun_file_path: rerun })
    Struct.new(:example).new(example)
  end

  def failing(id, exception)
    described_class.new.tap { |listener| listener.example_failed(notification(id, exception: exception)) }
  end

  def raised(klass, message, backtrace)
    klass.new(message).tap { |error| error.set_backtrace(backtrace) }
  end

  it "starts with a float zero runtime" do
    expect(described_class.new.runtime).to eql(0.0)
  end

  it "tells the recorder the example id and the expanded rerun file when an example starts" do
    recorder = double("recorder", test_started: nil)
    described_class.new(recorder).example_started(notification("t1", rerun: "./spec/a_spec.rb"))
    expect(recorder).to have_received(:test_started).with("t1", File.expand_path("./spec/a_spec.rb"))
  end

  it "needs no recorder to start or finish an example" do
    listener = described_class.new
    expect { listener.example_started(notification("t1")) }.not_to raise_error
    listener.example_finished(notification("t1"))
    expect(listener.executed).to eq(["t1"])
  end

  it "tells the recorder which example id finished" do
    recorder = double("recorder", test_finished: nil)
    described_class.new(recorder).example_finished(notification("t9"))
    expect(recorder).to have_received(:test_finished).with("t9")
  end

  it "records a failed id with a nil class and no detail when there is no exception" do
    listener = failing("t1", nil)
    expect(listener.failed).to eq(["t1"])
    expect(listener.failure_classes).to eq("t1" => nil)
    expect(listener.failure_messages).to eq("t1" => "")
    expect(listener.failure_details).to eq("t1" => nil)
  end

  it "records the class name, first line and class-prefixed detail of a failure" do
    listener = failing("t1", raised(ArgumentError, "bad\nsecond", ["./spec/a_spec.rb:3", "./lib/x.rb:9"]))
    expect(listener.failure_classes).to eq("t1" => "ArgumentError")
    expect(listener.failure_messages).to eq("t1" => "bad")
    expect(listener.failure_details["t1"]).to eq("ArgumentError: bad\nsecond\n./spec/a_spec.rb:3\n./lib/x.rb:9")
  end

  it "scrubs invalid bytes in backtrace frames of the detail" do
    frame = "./spec/\xFFa.rb:3".dup.force_encoding("UTF-8")
    detail = failing("t1", raised(RuntimeError, "m", [frame])).failure_details["t1"]
    expect(detail).to eq("RuntimeError: m\n#{Saboteur::Text.utf8(frame)}")
    expect(detail).to be_valid_encoding
  end

  it "caps the detail at 2000 characters and the first line at 200" do
    listener = failing("t1", RuntimeError.new("x" * 3000))
    expect(listener.failure_details["t1"].size).to eq(2000)
    expect(listener.failure_messages["t1"]).to eq("x" * 200)
  end

  it "dumps the message, capped, when building the detail raises" do
    allow(Saboteur::Text).to receive(:utf8).and_raise(RuntimeError, "mutant")
    klass = Class.new(StandardError) { def message = :custom }
    expect(failing("t1", klass.new).failure_details["t1"]).to eq('"custom"')
    expect(failing("t2", RuntimeError.new("y" * 3000)).failure_details["t2"].size).to eq(2000)
    expect(failing("t3", RuntimeError.new("z" * 3000)).failure_messages["t3"]).to eq(("z" * 3000).dump[0, 200])
  end

  it "keeps the first line of a nonblank message even when the message is a symbol-like object" do
    klass = Class.new(StandardError) { def message = :sym }
    expect(failing("t1", klass.new).failure_messages["t1"]).to eq("sym")
  end
end

RSpec.describe Saboteur::Integration::RSpec::LoadErrorReport, "pins" do
  let(:tool_root) { File.expand_path("../../..", __dir__) }
  let(:head) { "An error occurred while loading ./spec/%s_spec.rb.\n" }

  def block(name) = "#{format(head, name)}Failure: boom #{name}\n"

  it "returns text with no load error header unchanged" do
    expect(described_class.filter("just text\n\n")).to eq("just text\n\n")
  end

  it "returns a single load error unchanged" do
    text = "#{block('a')}\n"
    expect(described_class.filter(text)).to eq(text)
  end

  it "keeps the first of two errors and says one more was omitted" do
    text = "#{block('a')}\n#{block('b')}"
    expect(described_class.filter(text)).to eq(
      "#{block('a')}(1 more load error omitted; rerun with --verbose for the full list)\n"
    )
  end

  it "pluralizes and counts every error after the first" do
    text = "#{block('a')}\n#{block('b')}\n#{block('c')}"
    expect(described_class.filter(text)).to eq(
      "#{block('a')}(2 more load errors omitted; rerun with --verbose for the full list)\n"
    )
  end

  it "recognises a frame under the tool root, however indented" do
    expect(described_class.send(:saboteur_frame?, "  # #{tool_root}/lib/saboteur/a.rb:3:in 'x'\n")).to be(true)
  end

  it "does not treat other lines as tool frames" do
    expect(described_class.send(:saboteur_frame?, "#{tool_root}/lib/saboteur/a.rb:3:in 'x'")).to be(false)
    expect(described_class.send(:saboteur_frame?, "# ./spec/a_spec.rb:1:in 'x'")).to be(false)
    expect(described_class.send(:saboteur_frame?, "# /other/root/lib/saboteur/a.rb:1:in 'x'")).to be(false)
    expect(described_class.send(:saboteur_frame?, "plain text")).to be(false)
  end
end

RSpec.describe Saboteur::Integration::RSpec, "real_path pins" do
  it "falls back to the expanded path when the file does not exist" do
    expect(described_class.allocate.send(:real_path, "no/such/file.rb")).to eq(File.expand_path("no/such/file.rb"))
  end

  it "resolves an existing path through realpath" do
    expect(described_class.allocate.send(:real_path, __FILE__)).to eq(File.realpath(__FILE__))
  end
end
