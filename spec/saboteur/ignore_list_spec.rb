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

  def entry_for(digest, reason: "equivalent", state: nil, subject: "Person#adult?")
    extra = state ? ", state: #{state.inspect}" : ""
    <<~RUBY
      Saboteur.ignore do |i|
        i.mutation "#{digest}", subject: #{subject.inspect}, reason: #{reason.inspect}#{extra}
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

  it "defaults the triage state to accepted_equivalent" do
    with_file(entry_for("abc123")) do |path|
      expect(described_class.load(path).entries.first.state).to eq("accepted_equivalent")
    end
  end

  it "rejects an unknown triage state with the valid names" do
    with_file(entry_for("abc123", state: "later")) do |path|
      expect { described_class.load(path) }
        .to raise_error(Saboteur::ConfigError, /state.*accepted_equivalent, wont_fix, todo/)
    end
  end

  it "accepts a wont_fix survivor and records its triage state" do
    survivor = result_for(:survived)
    with_file(entry_for(survivor.digest, state: "wont_fix", reason: "dead code on legacy path")) do |path|
      warnings = described_class.load(path).apply([survivor])
      expect(survivor.ignored).to eq("dead code on legacy path")
      expect(survivor.triage_state).to eq("wont_fix")
      expect(warnings).to eq([])
    end
  end

  it "records a todo survivor without accepting it: it still counts" do
    survivor = result_for(:survived)
    with_file(entry_for(survivor.digest, state: "todo", reason: "fix in the next sprint")) do |path|
      described_class.load(path).apply([survivor])
      expect(survivor.ignored).to be_nil
      expect(survivor.unignored_survivor?).to be(true)
      expect([survivor.triage_state, survivor.triage_reason]).to eq(["todo", "fix in the next sprint"])
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
      expect(warnings).to eq(["stale ignore entry Person#adult? 0000000000000000: no such mutation " \
                              "- remove the entry or refresh its digest (saboteur survivors --show)"])
    end
  end

  # A subject with no unscoped candidate set at all (not built, say)
  # must read as stale, not blow up the warning pass (#284).
  it "calls an entry stale when the subject has no unscoped candidate set at all" do
    with_file(entry_for("0000000000000000", reason: "r")) do |path|
      warnings = described_class.load(path)
                                .apply([result_for(:survived)], unscoped_digests: {})
      expect(warnings).to eq(["stale ignore entry Person#adult? 0000000000000000: no such mutation " \
                              "- remove the entry or refresh its digest (saboteur survivors --show)"])
    end
  end

  # #627 advisory: a skipped `def K.b` and a real `def self.b` in one class
  # share the id "K.b". Digests are subject-start-relative, so an ignore
  # written for the real singleton cannot match - or be kept live by - the
  # skipped subject, which yields no results at all.
  it "never matches an ignore for a real singleton against a same-id skipped subject (#627)" do
    skipped, real = subjects_in("class K\n  def K.b; 1 + 1; end\n  def self.b; 1 + 1; end\nend\n", name: "k.rb")
    expect([skipped.id, skipped.skip_reason]).to eq(["K.b", "constant-receiver def"])
    expect(real.id).to eq("K.b")

    at = real.file_source.index("+", real.start_byte)
    edit = Saboteur::MutationSource::Edit.new(file: real.file, start_byte: at, end_byte: at + 1, replacement: "-")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: real.id, operator: "arithmetic", edits: [edit])
    digest = mutation.digest(subject_start: real.start_byte, original_source: real.file_source)
    # The same edit content under the skipped subject's start is a different digest.
    expect(mutation.digest(subject_start: skipped.start_byte, original_source: real.file_source)).not_to eq(digest)

    result = Saboteur::MutantResult.new(subject: real, mutation:, status: :survived,
                                        mutated_source: real.file_source.sub("+", "-"))
    with_file(entry_for(digest, subject: "K.b")) do |path|
      list = described_class.load(path)
      expect(list.apply([result])).to eq([])
      expect(result.ignored).not_to be_nil
      # The skipped subject alone examines nothing: no match, no stale call.
      expect(list.apply([])).to eq([])
    end
  end

  it "warns about entries for examined subjects whose mutation no longer exists" do
    with_file(entry_for("0000000000000000", reason: "r")) do |path|
      expect(described_class.load(path).apply([result_for(:survived)]))
        .to eq(["stale ignore entry Person#adult? 0000000000000000: no such mutation " \
                "- remove the entry or refresh its digest (saboteur survivors --show)"])
    end
  end

  it "warns when the same mutation is ignored twice, and the last entry wins (#1207)" do
    survivor = result_for(:survived)
    file = <<~RUBY
      Saboteur.ignore do |i|
        i.mutation "#{survivor.digest}", subject: "Person#adult?", reason: "first reason"
        i.mutation "#{survivor.digest}", subject: "Person#adult?", reason: "second reason"
        i.mutation "deadbeefdeadbeef", subject: "Person#old?", reason: "unique entry"
      end
    RUBY
    with_file(file) do |path|
      warnings = described_class.load(path).apply([survivor])
      expect(survivor.ignored).to eq("second reason")
      expect(warnings)
        .to eq(["duplicate ignore entry Person#adult? #{survivor.digest}: the last entry wins"])
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

  # A blank state is a pre-triage entry: it accepts (#304 dogfood).
  it "treats a blank state as accepted_equivalent" do
    with_file(entry_for("abc123", state: "")) do |path|
      expect(described_class.load(path).entries.first.state).to eq("accepted_equivalent")
    end
  end

  it "rejects an unknown state with the line, the state, and the valid states" do
    with_file(entry_for("abc123", state: "later")) do |path|
      expect { described_class.load(path) }.to raise_error(
        Saboteur::Error,
        /#{Regexp.escape(path)}:2: unknown state "later" - use one of accepted_equivalent, wont_fix, todo/
      )
    end
  end

  it "strips whitespace around the reason" do
    with_file(entry_for("abc123", reason: "  equivalent  ")) do |path|
      expect(described_class.load(path).entries.first.reason).to eq("equivalent")
    end
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

  it "is empty without a path" do
    expect(described_class.load(nil).entries).to eq([])
  end

  it "keeps only the first line of a load error, without its newline" do
    with_file(%(raise LoadError, "first line\\nsecond line"\n)) do |path|
      expect { described_class.load(path) }
        .to raise_error(Saboteur::ConfigError) { |error| expect(error.message).to eq("#{path}: first line") }
    end
  end

  it "copes with an empty load error message" do
    with_file(%(raise LoadError, ""\n)) do |path|
      expect { described_class.load(path) }
        .to raise_error(Saboteur::ConfigError) { |error| expect(error.message).to eq("#{path}: ") }
    end
  end

  it "reports a bare constant with the line in the ignore file and a boot hint" do
    with_file("\nMissingIgnoreConstant\n") do |path|
      expect { described_class.load(path) }.to raise_error(
        Saboteur::ConfigError,
        "#{path}:2: uninitialized constant MissingIgnoreConstant " \
        "- this file loads before the app boots; use plain Ruby or ENV"
      )
    end
  end

  it "points a name error at the ignore file's line, not at the frame that raised it" do
    stub_const("IgnoreListSpecRaiser", -> { raise NameError, "undefined name zz\nsecond line" })
    with_file("\nIgnoreListSpecRaiser.call\n") do |path|
      expect { described_class.load(path) }.to raise_error(
        Saboteur::ConfigError,
        "#{path}:2: undefined name zz - this file loads before the app boots; use plain Ruby or ENV"
      )
    end
  end

  it "gives a typo outside the collector the same treatment as a bare constant" do
    with_file("\nnil.no_such_call\n") do |path|
      expect { described_class.load(path) }.to raise_error(Saboteur::ConfigError, /\A#{path}:2: undefined method/)
    end
  end

  it "points an unknown directive at the ignore file's line with the full hint" do
    with_file("Saboteur.ignore do |i|\n  i.skip \"abc\"\nend\n") do |path|
      expect { described_class.load(path) }.to raise_error(
        Saboteur::ConfigError,
        %(#{path}:2: unknown directive "skip" - declare entries with mutation "<digest>", subject:, reason:)
      )
    end
  end

  it "copes with an empty name error message" do
    stub_const("IgnoreListSpecRaiser", -> { raise NameError, "" })
    with_file("\nIgnoreListSpecRaiser.call\n") do |path|
      expect { described_class.load(path) }.to raise_error(
        Saboteur::ConfigError, "#{path}:2:  - this file loads before the app boots; use plain Ruby or ENV"
      )
    end
  end

  it "points an unknown directive raised elsewhere at the ignore file's line" do
    stub_const("IgnoreListSpecRaiser", -> { described_class.current_collector.bogus })
    with_file("\nIgnoreListSpecRaiser.call\n") do |path|
      expect { described_class.load(path) }
        .to raise_error(Saboteur::ConfigError, /\A#{path}:2: unknown directive "bogus"/)
    end
  end

  it "reports a syntax error with the file" do
    with_file("Saboteur.ignore do |i|\n") do |path|
      expect { described_class.load(path) }.to raise_error(Saboteur::Error, /saboteur_ignore\.rb/)
    end
  end

  it "normalizes a non-string digest the way it normalizes strings (#304 dogfood)" do
    content = <<~RUBY
      Saboteur.ignore do |i|
        i.mutation 123, subject: "Person#adult?", reason: "r"
      end
    RUBY
    with_file(content) do |path|
      expect(described_class.load(path).entries.map(&:mutation)).to eq(["123"])
    end
  end

  it "normalizes a non-string reason the way it normalizes strings (#304 dogfood)" do
    content = <<~RUBY
      Saboteur.ignore do |i|
        i.mutation "abc", subject: "Person#adult?", reason: 42
      end
    RUBY
    with_file(content) do |path|
      expect(described_class.load(path).entries.map(&:reason)).to eq(["42"])
    end
  end

  it "normalizes a non-string subject the way it normalizes strings (#304 dogfood)" do
    content = <<~RUBY
      Saboteur.ignore do |i|
        i.mutation "abc", subject: :"Person#adult?", reason: "r"
      end
    RUBY
    with_file(content) do |path|
      expect(described_class.load(path).entries.map(&:subject)).to eq(["Person#adult?"])
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

  # A reason split across lines without a continuation backslash silently
  # keeps only its first line, so guard the shipped file against truncated
  # reasons (they always end in the first line's trailing space).
  it "keeps every reason in the shipped ignore file complete" do
    config = File.expand_path("../../config/saboteur_ignore.rb", __dir__)
    reasons = described_class.load(config).entries.map(&:reason)
    expect(reasons).to all(match(/\S\z/))
  end

  it "drops its collector after a load, whether the file loads or raises" do
    with_file(entry_for("abc123")) { |path| described_class.load(path) }
    expect(described_class.instance_variable_get(:@collector)).to be_nil
    with_file("raise 'boom'\n") do |path|
      expect { described_class.load(path) }.to raise_error(RuntimeError, "boom")
    end
    expect(described_class.instance_variable_get(:@collector)).to be_nil
  end
end
