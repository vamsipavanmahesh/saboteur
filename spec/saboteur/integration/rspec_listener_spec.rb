# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Integration::RSpec::Listener do
  def failed(id, exception)
    result = Struct.new(:exception).new(exception)
    example = Struct.new(:id, :execution_result).new(id, result)
    described_class.new.tap { |listener| listener.example_failed(Struct.new(:example).new(example)) }
  end

  # A verdict that does not hold up should say why the test failed.
  it "keeps the first line of each failure message, at most 200 characters" do
    listener = failed("t1", RuntimeError.new("\nexpected: 2\n     got: 3"))
    expect(listener.failure_messages).to eq({ "t1" => "expected: 2" })
    expect(failed("t2", RuntimeError.new("x" * 500)).failure_messages["t2"].size).to eq(200)
  end

  it "records the exception class" do
    expect(failed("t1", NoMethodError.new("m")).failure_classes).to eq({ "t1" => "NoMethodError" })
  end
end
