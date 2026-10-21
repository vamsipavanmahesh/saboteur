# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "stringio"
require "tmpdir"

# PR14 pins: --survivors re-run (RSpec --only-failures analog) - selection,
# conflicts, exits, wording, the score-history guard, the report guard.
RSpec.describe "saboteur run --survivors" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def cli(*argv)
    Saboteur::CLI.new(argv, out:, err:)
  end

  def fixture_report(mutants)
    { "schemaVersion" => "2",
      "files" => { "lib/order.rb" => { "language" => "ruby", "source" => "a\nb\n", "mutants" => mutants } },
      "saboteur" => { "findings" => { "version" => 1, "survivors" => [], "accepted" => [] } } }
  end

  def mutant(digest, status)
    { "id" => digest, "mutatorName" => "comparison", "replacement" => ">",
      "location" => { "start" => { "line" => 1, "column" => 1 }, "end" => { "line" => 1, "column" => 2 } },
      "status" => status, "coveredBy" => [] }
  end

  describe Saboteur::CLI::SurvivorsBrowser do
    it "reads exactly the unignored survivors' digests from the files section" do
      report = fixture_report([mutant("a" * 16, "Survived"), mutant("b" * 16, "Ignored"),
                               mutant("c" * 16, "Killed"), mutant("d" * 16, "Survived")])
      expect(described_class.new(report).survivor_digests).to eq(["a" * 16, "d" * 16])
    end
  end

  describe Saboteur::Engine, "survivor selection" do
    let(:subject) { person_subject }
    let(:mutation) { comparison_mutation }
    let(:digest) { mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source) }
    let(:candidate) { [mutation, subject.apply(mutation.edits)] }
    let(:gone) { "0" * 16 }

    def engine(digests)
      config = Saboteur::Config.new({ "all" => true })
      described_class.new(config, err: StringIO.new,
                                  survivors: { digests:, source: ".saboteur/report.json" })
    end

    it "keeps exactly the mutants the digests name, reports the rest as gone, names the report" do
      run = engine([digest, gone])
      expect(run.send(:survivor_lists, [subject], [[candidate]])).to eq([[candidate]])
      expect(run.send(:survivors_rerun)).to eq(source: ".saboteur/report.json", gone: [gone])
      expect(run.send(:start_scope)).to eq("2 survivors from .saboteur/report.json")
    end
  end

  describe "flag conflicts" do
    it "rejects --survivors with --since, --all-mutants or --id as a usage error" do
      [["--since", "main"], ["--all-mutants"], ["--id", "a" * 16]].each do |args|
        expect(cli("run", "--survivors", *args).call).to eq(2)
        expect(err.string).to include("--survivors cannot be combined with #{args.first}")
      end
    end
  end

  describe "the run itself" do
    around do |example|
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "lib"))
        File.write(File.join(dir, "lib", "a.rb"), "class A; end\n")
        Dir.chdir(dir) { example.run }
      end
    end

    it "exits 0 with a note when the report has no unignored survivors" do
      File.write("report.json", JSON.generate(fixture_report([mutant("a" * 16, "Killed")])))
      allow(Saboteur::Engine).to receive(:new).and_raise(Saboteur::Error, "must not boot")
      expect(cli("run", "--survivors", "report.json").call).to eq(0)
      expect(out.string).to include("no unignored survivors in report.json - nothing to re-run")
      expect(Saboteur::Engine).not_to have_received(:new)
    end

    it "rejects a JSON file that is not a saboteur report as a usage error" do
      File.write("report.json", JSON.generate({ "some" => "json" }))
      expect(cli("run", "--survivors", "report.json").call).to eq(2)
      expect(err.string).to include("report.json is not a saboteur report (no files/saboteur sections)")
    end

    it "hands the report's digests to the engine and never appends to the score history" do
      File.write("report.json", JSON.generate(fixture_report([mutant("a" * 16, "Survived")])))
      engine = instance_double(Saboteur::Engine)
      allow(Saboteur::Engine).to receive(:new).and_return(engine)
      allow(engine).to receive(:call).and_return(report_of(result_for(:killed)))
      history = class_spy(Saboteur::Reporter::ScoreHistory)
      stub_const("Saboteur::Reporter::ScoreHistory", history)
      expect(cli("run", "--survivors", "report.json").call).to eq(0)
      expect(Saboteur::Engine).to have_received(:new)
        .with(anything, hash_including(survivors: { digests: ["a" * 16], source: "report.json" }))
      expect(history).not_to have_received(:new)
    end
  end

  describe Saboteur::Reporter::Terminal, "rerun wording" do
    let(:terminal_out) { StringIO.new }

    def render(report, exit_code: 1)
      Saboteur::Reporter::Terminal.new(terminal_out, color: :never, threshold: nil, replay_command: nil,
                                                     all_mutants: false, exit_code:, previous_score: nil,
                                                     baseline_gate: nil).call(report)
      terminal_out.string
    end

    def rerun_report(gone: ["0" * 16], results: [result_for(:killed), result_for(:killed, reused: true),
                                                 result_for(:survived)])
      Saboteur::Report.new(results:, subjects: [person_subject], wall_time: 4.1,
                           root: File.dirname(person_subject.file), seed: 1,
                           survivors_rerun: { source: ".saboteur/report.json", gone: })
    end

    it "names gone digests in the canonical line and scores only the re-run" do
      text = render(rerun_report)
      expect(text).to include("saboteur: 2 killed, 1 survived, 1 digest gone (code changed) in 4s")
      expect(text).to include("score 66.7% of re-run survivors")
      expect(text).to include("gone digests: #{'0' * 16}")
    end

    it "keeps the gone-digests note on a clean re-run screen" do
      expect(render(rerun_report(results: [result_for(:killed)]), exit_code: 0))
        .to include("gone digests: #{'0' * 16}")
    end
  end
end
