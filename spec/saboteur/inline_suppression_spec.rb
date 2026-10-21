# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::InlineSuppression do
  def target(comment, prefix: "")
    subjects_in("#{prefix}class SuppressionTarget\n  def m(x)\n    x + 1 #{comment}\n    x * 2\n  end\nend\n").first
  end

  def candidates(subject)
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    list = Saboteur::Engine::Candidates.new([Saboteur::MutationSource::Builtin.new], diagnostics).for(subject)
    [list, diagnostics]
  end

  it "compares directive scope with exact relative lines, sorted operators and reasons" do
    subject = target('# saboteur:disable-line literal_number arithmetic reason="scope"')
    parser = described_class.new(subject.file, subject.file_source)
    expect(parser.signature(subject)).to eq([[1, %w[arithmetic literal_number], "scope"]])
    later = subjects_in("class Later\n  def other(x)\n    x + 1\n  end\nend\n").first
    expect(described_class.new(later.file, later.file_source).signature(later)).to eq([])
  end

  it "suppresses all edits starting on the directive line and records each reason" do
    subject = target('# saboteur:disable-line reason="covered elsewhere"')
    list, diagnostics = candidates(subject)
    edits = list.flat_map { |mutation, _| mutation.edits }
    expect(edits.map { |edit| subject.line_of(edit.start_byte) }).not_to include(3)
    expect(diagnostics.inline_suppressions).not_to be_empty
    expect(diagnostics.inline_suppressions.map { |entry| entry[:reason] }.uniq).to eq(["covered elsewhere"])
    expect(list.any? { |mutation, _| mutation.operator == "arithmetic" }).to be(true)
  end

  it "restricts operators and survives a code move" do
    ["", "# moved\n\n"].each do |prefix|
      subject = target('# saboteur:disable-line arithmetic reason="same behavior"', prefix: prefix)
      list, diagnostics = candidates(subject)
      expect(diagnostics.inline_suppressions.map { |entry| entry[:operator] }).to eq(["arithmetic"])
      expect(list.any? { |mutation, _| mutation.operator == "literal_number" }).to be(true)
    end
  end

  it "rejects missing blank unknown or malformed directives with a source location" do
    ["# saboteur:disable-line", '# saboteur:disable-line reason=" "',
     '# saboteur:disable-line typo reason="why"', '# saboteur:disable-line reason="'].each do |comment|
      subject = target(comment)
      expect { candidates(subject) }.to raise_error(Saboteur::ConfigError, /#{Regexp.escape(subject.file)}:3:/)
    end
  end

  it "ignores string contents and unrelated lines" do
    subject = subjects_in(<<~RUBY).first
      class StringSuppression
        def m
          "# saboteur:disable-line reason=oops"
          2
        end
      end
      # saboteur:disable-line reason="unrelated"
    RUBY
    expect(candidates(subject).last.inline_suppressions).to eq([])
  end

  it "uses the edit's starting line in a multi-line expression" do
    subject = subjects_in(<<~RUBY).first
      class MultilineSuppression
        def m(x)
          x + # saboteur:disable-line arithmetic reason="covered"
            1
        end
      end
    RUBY
    list, diagnostics = candidates(subject)
    expect(diagnostics.inline_suppressions.map { |entry| entry[:operator] }).to eq(["arithmetic"])
    expect(list.any? { |mutation, _| mutation.operator == "literal_number" }).to be(true)
  end

  it "audits suppressions in every report without changing score or survivor counts" do
    subject = target('# saboteur:disable-line arithmetic reason="why <now>"')
    _list, diagnostics = candidates(subject)
    report = Saboteur::Report.new(results: [], subjects: [subject], root: File.dirname(subject.file), wall_time: 0,
                                  inline_suppressions: diagnostics.inline_suppressions)
    out = StringIO.new
    Saboteur::Reporter::Terminal.new(out).call(report)
    expect(out.string).to include("Inline suppressions: 1", "why <now>")
    expect(Saboteur::Reporter::Stryker.build(report).dig(:saboteur,
                                                         :inlineSuppressions).first[:reason]).to eq("why <now>")
    expect(Saboteur::Reporter::Html.build(report)).to include("Inline suppressions (1", "why &lt;now&gt;")
    expect(report.score).to be_nil
    expect(report.unignored_survivors).to be_empty
  end
  it "records a complete audit row with source location and stable candidate identity" do
    subject = target('# saboteur:disable-line arithmetic reason="audit"')
    _list, diagnostics = candidates(subject)
    entry = diagnostics.inline_suppressions.first
    mutation = Saboteur::MutationSource::Builtin.new.mutations_for(subject).find { |item| item.operator == "arithmetic" }
    digest = mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
    expect(entry).to eq(file: subject.file, line: 3, subject: subject.id, operator: "arithmetic", reason: "audit",
                        digest: digest)
    report = Saboteur::Report.new(results: [], subjects: [subject], root: File.dirname(subject.file), wall_time: 0,
                                  inline_suppressions: diagnostics.inline_suppressions)
    rows = Saboteur::Reporter::Stryker.build(report).dig(:saboteur, :inlineSuppressions)
    expect(rows.first[:file]).to eq(File.basename(subject.file))
  end

  it "wires engine diagnostics into the completed report" do
    subject = target('# saboteur:disable-line arithmetic reason="audit"')
    _list, diagnostics = candidates(subject)
    engine = Saboteur::Engine.new(Saboteur::Config.new({}))
    engine.instance_variable_set(:@diagnostics, diagnostics)
    report = engine.send(:build_report, [], [subject], nil, Process.clock_gettime(Process::CLOCK_MONOTONIC))
    expect(report.inline_suppressions).to eq(diagnostics.inline_suppressions)
  end

  it "validates malformed comments even outside selected methods" do
    subject = target("# unrelated")
    File.write(subject.file, "#{subject.file_source}# saboteur:disable-line\n")
    config = Saboteur::Config.new({}, root: File.dirname(subject.file))
    selection = Saboteur::Engine::SubjectSelection.new(config, Saboteur::Engine::Diagnostics.new(StringIO.new))
    expect { selection.select([subject.file]) }.to raise_error(Saboteur::ConfigError, /:7:/)
  end

  it "does not print empty audit headings" do
    report = report_of
    out = StringIO.new
    Saboteur::Reporter::Terminal.new(out).call(report)
    expect(out.string).not_to include("Inline suppressions")
    expect(Saboteur::Reporter::Html.build(report)).not_to include("Inline suppressions")
  end
  it "keeps searching later edits when the first has no matching directive" do
    subject = target('# saboteur:disable-line arithmetic reason="second edit"')
    source = Saboteur::MutationSource::Builtin.new.mutations_for(subject)
    first = source.find { |m| m.operator == "arithmetic" && subject.line_of(m.edits.first.start_byte) == 4 }
    second = source.find { |m| m.operator == "arithmetic" && subject.line_of(m.edits.first.start_byte) == 3 }
    mutation = first.with(edits: first.edits + second.edits)
    directive = described_class.new(subject.file, subject.file_source).reason(subject, mutation)
    expect(directive.reason).to eq("second edit")
    expect(directive.line).to eq(3)
  end

  it "reports exact errors for similar directive tokens and unknown operator lists" do
    {
      "# saboteur:disable-lines reason=why" => "expected saboteur:disable-line",
      "# saboteur:disable-line typo another reason=why" => "unknown operators: typo, another"
    }.each do |comment, message|
      subject = target(comment)
      expect { described_class.new(subject.file, subject.file_source) }
        .to raise_error(Saboteur::ConfigError, "#{subject.file}:3: #{message}")
    end
  end

  it "leaves directives on lines outside the subject out of its signature" do
    subject = target('# saboteur:disable-line reason="inside"', prefix: "# saboteur:disable-line reason=\"above\"\n")
    parser = described_class.new(subject.file, subject.file_source)
    expect(parser.signature(subject)).to eq([[1, [], "inside"]])
  end

  it "reads a directive written without a space after the hash" do
    subject = target('#saboteur:disable-line reason="tight"')
    expect(described_class.new(subject.file, subject.file_source).signature(subject)).to eq([[1, [], "tight"]])
  end

  it "reports the exact invalid suppression message for an unterminated quote" do
    subject = target('# saboteur:disable-line reason="')
    shell_message = begin
      Shellwords.split('saboteur:disable-line reason="')
    rescue ArgumentError => e
      e.message
    end
    expect { described_class.new(subject.file, subject.file_source) }
      .to raise_error(Saboteur::ConfigError, "#{subject.file}:3: invalid suppression: #{shell_message}")
  end

  it "rejects absent blank and multiple reasons with the required diagnostic" do
    ["# saboteur:disable-line", '# saboteur:disable-line reason=" "',
     "# saboteur:disable-line reason=one reason=two"].each do |comment|
      subject = target(comment)
      expect { described_class.new(subject.file, subject.file_source) }
        .to raise_error(Saboteur::ConfigError, /:3: one nonblank reason=/)
    end
  end
  it "forwards suppression and discovery scope to baseline finish" do
    engine = Saboteur::Engine.new(Saboteur::Config.new({}))
    capture = double("capture")
    diagnostics = engine.instance_variable_get(:@diagnostics)
    failure = Saboteur::Engine::Diagnostics::DiscoveryFailure.new(file: "broken.rb", reason: "invalid")
    diagnostics.discovery_failures << failure
    diagnostics.inline_suppressions << { file: "source.rb", digest: "abc" }
    engine.instance_variable_set(:@run_evidence, capture)
    engine.instance_variable_set(:@evidence_planned, true)
    expect(capture).to receive(:finish).with(hash_including(discovery_failures: [failure],
                                                            inline_suppressions: diagnostics.inline_suppressions))
    engine.send(:complete_evidence, [], [])
  end
end
