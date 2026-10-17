# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::Gates do
  def gates(settings = {})
    described_class.new({ "max_timeouts" => nil, "max_errors" => nil }.merge(settings))
  end

  def report(*statuses)
    report_of(*statuses.map { |status| result_for(status) })
  end

  describe ".limit" do
    it "reads a count, a percentage, or nothing" do
      expect(described_class.limit(nil, "max_errors")).to be_nil
      expect(described_class.limit("3", "max_errors")).to eq(3)
      expect(described_class.limit(0, "max_errors")).to eq(0)
      expect(described_class.limit(" 5% ", "max_errors")).to eq("5%")
      expect(described_class.limit("007", "max_errors")).to eq(7)
      expect(described_class.limit("05%", "max_errors")).to eq("5%")
      expect(described_class.limit("100%", "max_errors")).to eq("100%")
    end

    it "allows a count above 100, since only a percentage is capped" do
      expect(described_class.limit("250", "max_errors")).to eq(250)
    end

    it "refuses anything else and names the setting" do
      ["-1", "2.5", "abc", "", "101%", "%"].each do |value|
        expect { described_class.limit(value, "max_timeouts") }
          .to raise_error(Saboteur::ConfigError, /max_timeouts must be a count|max_timeouts percentage/), value
      end
    end
  end

  describe "per-path score gates (#473)" do
    around do |example|
      Dir.mktmpdir do |dir|
        @root = File.realpath(dir)
        example.run
      end
    end

    def subject_at(relative, index)
      path = File.join(@root, relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "class Klass#{index}\n  def a; 1 > 0; end\nend\n")
      Saboteur::SubjectFinder.new.call(path).subjects.first
    end

    def result_on(subject, status)
      at = subject.file_source.index(">")
      edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 1,
                                                replacement: ">=")
      mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "comparison",
                                                        edits: [edit])
      Saboteur::MutantResult.new(subject:, mutation:, status:,
                                 mutated_source: subject.apply(mutation.edits))
    end

    def report_with(pairs)
      results = pairs.map { |subject, status| result_on(subject, status) }
      Saboteur::Report.new(results:, subjects: results.map(&:subject), wall_time: 1.0, root: @root,
                           warnings: [], seed: 1,
                           operator_policy: Saboteur::Config.new({}).operator_policy)
    end

    def score_gates(pattern, min_score)
      described_class.new({ "max_timeouts" => nil, "max_errors" => nil,
                            "score_gates" => [{ "pattern" => pattern, "min_score" => min_score }] })
    end

    it "fails when a path gate's subset scores under its floor" do
      charge = subject_at("app/payments/charge.rb", 1)
      old = subject_at("app/legacy/old.rb", 2)
      report = report_with([[charge, :killed], [charge, :survived], [old, :killed], [old, :killed]])
      found = score_gates("app/payments/**/*", 90).violations(report)
      expect(found.map(&:cause)).to eq(["scoreGate"])
      expect(found.first.message).to include("app/payments/**/*", "50", "90")
    end

    it "passes when the subset meets its floor" do
      charge = subject_at("app/payments/charge.rb", 1)
      report = report_with([[charge, :killed], [charge, :survived]])
      expect(score_gates("app/payments/**/*", 50).violations(report)).to be_empty
    end

    it "passes vacuously when nothing executed under the gate, and says so" do
      charge = subject_at("app/payments/charge.rb", 1)
      report = report_with([[charge, :killed]])
      err = StringIO.new
      expect(score_gates("app/legacy/**/*", 95).failed?(report, err)).to be(false)
      expect(err.string).to include("app/legacy/**/*", "nothing executed")
    end

    it "counts toward any?, so --agent refuses the combination like --threshold" do
      expect(score_gates("app/**/*", 95).any?).to be(true)
    end
  end

  describe "#violations" do
    it "passes when no gate is set, whatever the counts" do
      expect(gates.violations(report(:timeout, :error, :killed))).to be_empty
      expect(gates.any?).to be(false)
    end

    it "fails a count only when it is above the limit" do
      limit = gates("max_timeouts" => 1)
      expect(limit.violations(report(:timeout, :killed))).to be_empty
      found = limit.violations(report(:timeout, :timeout, :killed)).first
      expect(found.cause).to eq("maxTimeouts")
      expect(found.message).to eq("2 timeout mutants, above --max-timeouts 1")
    end

    it "treats a limit of 0 as no timeouts at all" do
      expect(gates("max_errors" => 0).violations(report(:killed, :killed))).to be_empty
      expect(gates("max_errors" => 0).violations(report(:killed, :killed, :killed, :error)).map(&:cause))
        .to eq(["maxErrors"])
    end

    it "compares a percentage with the executed mutants and ignores skipped ones" do
      limit = gates("max_errors" => "25%")
      expect(limit.violations(report(:error, :killed, :killed, :killed))).to be_empty
      expect(limit.violations(report(:error, :error, :killed, :killed, :killed, :skipped)).map(&:cause))
        .to eq(["maxErrors"])
    end

    it "is over a percentage only by the exact ratio" do
      limit = gates("max_errors" => "10%")
      expect(limit.violations(report(*[:error] * 100, *[:killed] * 900))).to be_empty
      expect(limit.violations(report(*[:error] * 100, *[:killed] * 899)).map(&:cause)).to eq(["maxErrors"])
      expect(limit.violations(report(*[:error] * 100, *[:killed] * 901))).to be_empty
    end

    it "reports each failed gate" do
      both = gates("max_timeouts" => 0, "max_errors" => 0)
      expect(both.violations(report(:timeout, :error, :killed, :killed, :killed)).map(&:cause))
        .to eq(%w[maxTimeouts maxErrors])
    end
  end

  describe "#failed?" do
    it "names the first failed gate as the cause when several fail" do
      both = gates("max_timeouts" => 0, "max_errors" => 0)
      expect(both.failed?(report(:timeout, :error, :killed), StringIO.new)).to be(true)
      expect(both.cause).to eq("maxTimeouts")
    end

    it "prints each failed gate and remembers the first cause" do
      err = StringIO.new
      limit = gates("max_timeouts" => 0)
      expect(limit.failed?(report(:timeout, :killed), err)).to be(true)
      expect(err.string).to eq("saboteur: 1 timeout mutants, above --max-timeouts 0\n")
      expect(limit.cause).to eq("maxTimeouts")
    end

    it "stays quiet and has no cause when every gate holds" do
      err = StringIO.new
      limit = gates("max_timeouts" => 5)
      expect(limit.failed?(report(:timeout, :killed), err)).to be(false)
      expect([err.string, limit.cause, limit.judges_errors?]).to eq(["", nil, false])
      expect(gates("max_errors" => 1).judges_errors?).to be(true)
    end
  end

  it "defines one flag per gate and passes the config key and raw value on" do
    parser = OptionParser.new
    given = {}
    described_class.define_options(parser) { |key, value| given[key] = value }
    parser.parse!(%w[--max-timeouts 3 --max-errors 5%])
    expect(given).to eq(max_timeouts: "3", max_errors: "5%")
    expect(parser.to_s).to include("--max-timeouts N", "--max-errors N",
                                   "Exit 1 when more than N mutants end as timeout (N or N%)",
                                   "Exit 1 when more than N mutants end as error (N or N%)")
  end
end
