# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::IgnoreList do
  def with_file(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "ignore.yml")
      File.write(path, content)
      yield path
    end
  end

  it "is empty when the file does not exist" do
    expect(described_class.load("/nonexistent/ignore.yml").entries).to eq([])
  end

  it "marks matching survivors as ignored with the reason" do
    survivor = result_for(:survived)
    with_file(<<~YAML) do |path|
      - subject: "Person#adult?"
        mutation: "#{survivor.digest}"
        reason: "equivalent: ages are whole years"
    YAML
      warnings = described_class.load(path).apply([survivor])
      expect(survivor.ignored).to eq("equivalent: ages are whole years")
      expect(warnings).to eq([])
    end
  end

  it "never marks a killed mutant as ignored" do
    killed = result_for(:killed)
    with_file("- {subject: 'Person#adult?', mutation: '#{killed.digest}', reason: r}\n") do |path|
      described_class.load(path).apply([killed])
      expect(killed.ignored).to be_nil
    end
  end

  it "warns about entries for examined subjects whose mutation no longer exists" do
    with_file("- {subject: 'Person#adult?', mutation: '0000000000000000', reason: r}\n") do |path|
      expect(described_class.load(path).apply([result_for(:survived)]))
        .to eq(["stale ignore entry Person#adult? 0000000000000000: no such mutation"])
    end
  end

  it "requires a reason" do
    with_file("- {subject: 'Person#adult?', mutation: 'abc', reason: '  '}\n") do |path|
      expect { described_class.load(path) }.to raise_error(Saboteur::Error, /entry 1 is missing reason/)
    end
  end

  it "rejects a file that is not a list" do
    with_file("subject: x\n") do |path|
      expect { described_class.load(path) }.to raise_error(Saboteur::Error, /list/)
    end
  end
end
