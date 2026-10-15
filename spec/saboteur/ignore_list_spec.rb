# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::IgnoreList do
  def with_file(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "saboteur_ignore.rb")
      File.write(path, content)
      yield path
    end
  end

  def entry_for(digest, reason: "equivalent")
    <<~RUBY
      Saboteur.ignore do |i|
        i.mutation "#{digest}", subject: "Person#adult?", reason: #{reason.inspect}
      end
    RUBY
  end

  it "is empty when the file does not exist" do
    expect(described_class.load("/nonexistent/saboteur_ignore.rb").entries).to eq([])
  end

  it "marks matching survivors as ignored with the reason" do
    survivor = result_for(:survived)
    with_file(entry_for(survivor.digest, reason: "equivalent: ages are whole years")) do |path|
      warnings = described_class.load(path).apply([survivor])
      expect(survivor.ignored).to eq("equivalent: ages are whole years")
      expect(warnings).to eq([])
    end
  end

  it "never marks a killed mutant as ignored" do
    killed = result_for(:killed)
    with_file(entry_for(killed.digest, reason: "r")) do |path|
      described_class.load(path).apply([killed])
      expect(killed.ignored).to be_nil
    end
  end

  # A scoped run (--since) drops mutants on unchanged lines before results
  # exist; an entry matching one of those dropped mutants is not stale (#284).
  it "does not call an entry stale when the digest survives in the subject's unscoped candidates" do
    with_file(entry_for("0000000000000000", reason: "r")) do |path|
      warnings = described_class.load(path)
                                .apply([result_for(:survived)],
                                       unscoped_digests: { "Person#adult?" => ["0000000000000000"] })
      expect(warnings).to eq([])
    end
  end

  it "still calls an entry stale when the digest is in no unscoped candidate set" do
    with_file(entry_for("0000000000000000", reason: "r")) do |path|
      warnings = described_class.load(path)
                                .apply([result_for(:survived)],
                                       unscoped_digests: { "Person#adult?" => ["ffffffffffffffff"] })
      expect(warnings).to eq(["stale ignore entry Person#adult? 0000000000000000: no such mutation"])
    end
  end

  # A subject with no unscoped candidate set at all (not built, say)
  # must read as stale, not blow up the warning pass (#284).
  it "calls an entry stale when the subject has no unscoped candidate set at all" do
    with_file(entry_for("0000000000000000", reason: "r")) do |path|
      warnings = described_class.load(path)
                                .apply([result_for(:survived)], unscoped_digests: {})
      expect(warnings).to eq(["stale ignore entry Person#adult? 0000000000000000: no such mutation"])
    end
  end

  it "warns about entries for examined subjects whose mutation no longer exists" do
    with_file(entry_for("0000000000000000", reason: "r")) do |path|
      expect(described_class.load(path).apply([result_for(:survived)]))
        .to eq(["stale ignore entry Person#adult? 0000000000000000: no such mutation"])
    end
  end

  it "requires a reason" do
    with_file(entry_for("abc", reason: "  ")) do |path|
      expect do
        described_class.load(path)
      end.to raise_error(Saboteur::Error, /saboteur_ignore\.rb:2: entry is missing reason/)
    end
  end

  it "requires a subject" do
    content = <<~RUBY
      Saboteur.ignore do |i|
        i.mutation "abc", reason: "equivalent"
      end
    RUBY
    with_file(content) do |path|
      expect do
        described_class.load(path)
      end.to raise_error(Saboteur::Error, /saboteur_ignore\.rb:2: entry is missing subject/)
    end
  end

  it "refuses Saboteur.ignore while no ignore file loads" do
    expect { Saboteur.ignore { |i| i.mutation "abc", subject: "X#y", reason: "r" } }
      .to raise_error(RuntimeError, "Saboteur.ignore is only valid while config/saboteur_ignore.rb loads")
  end

  it "pins the full missing-reason message" do
    content = <<~RUBY
      Saboteur.ignore do |i|
        i.mutation "abc", subject: "Person#adult?"
      end
    RUBY
    with_file(content) do |path|
      expect { described_class.load(path) }
        .to raise_error(Saboteur::Error, "#{path}:2: entry is missing reason")
    end
  end

  it "refuses an unknown directive with the file and line" do
    content = <<~RUBY
      Saboteur.ignore do |i|
        i.skip "abc"
      end
    RUBY
    with_file(content) do |path|
      expect { described_class.load(path) }
        .to raise_error(Saboteur::Error, /saboteur_ignore\.rb:2: unknown directive "skip"/)
    end
  end

  it "reports a syntax error with the file" do
    with_file("Saboteur.ignore do |i|\n") do |path|
      expect { described_class.load(path) }.to raise_error(Saboteur::Error, /saboteur_ignore\.rb/)
    end
  end

  it "requires a mutation digest" do
    content = <<~RUBY
      Saboteur.ignore do |i|
        i.mutation subject: "Person#adult?", reason: "equivalent"
      end
    RUBY
    with_file(content) do |path|
      expect { described_class.load(path) }
        .to raise_error(Saboteur::Error, "#{path}:2: entry is missing mutation")
    end
  end

  it "lists every missing field" do
    with_file("Saboteur.ignore { |i| i.mutation }\n") do |path|
      expect { described_class.load(path) }
        .to raise_error(Saboteur::Error, "#{path}:1: entry is missing subject, mutation, reason")
    end
  end

  it "wraps a NoMethodError from a non-collector receiver" do
    with_file("[].bogus\n") do |path|
      expect { described_class.load(path) }.to raise_error(Saboteur::ConfigError) { |error|
        expect(error.message).to include("saboteur_ignore.rb:1:", "before the app boots")
        expect(error.message).to match(/[`']bogus'/)
      }
    end
  end

  it "returns the collector from Saboteur.ignore" do
    content = "raise 'no collector' unless Saboteur.ignore { |i| }.is_a?(Saboteur::IgnoreList::Collector)\n"
    with_file(content) do |path|
      expect { described_class.load(path) }.not_to raise_error
    end
  end
end
