# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "stringio"
require "tmpdir"

# saboteur survivors <report.json> (#475): a read-only terminal browser for
# the Stryker JSON report. No project boot, no test reruns.
RSpec.describe Saboteur::CLI, "survivors (#475)" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def cli(*argv)
    described_class.new(argv, out:, err:)
  end

  def mutant(id:, operator:, line:, status:, classification: nil, covered: ["./spec/order_spec.rb[1:1]"],
             replacement: "items.map(&:price).sum")
    entry = { "id" => id, "mutatorName" => operator, "replacement" => replacement,
              "location" => { "start" => { "line" => line, "column" => 3 },
                              "end" => { "line" => line, "column" => 24 } },
              "status" => status, "coveredBy" => covered }
    classification ? entry.merge("classification" => classification) : entry
  end

  def write_report(dir, survivors:)
    source = <<~RUBY_SRC
      class Order
        def total(items)
          items.sum(&:price)
        end
      end
    RUBY_SRC
    digest_a = "a" * 16
    mutants = [mutant(id: digest_a, operator: "sum_to_map_sum", line: 3, status: "Survived",
                      classification: "boundary"),
               mutant(id: "b" * 16, operator: "and_to_or", line: 3, status: "Survived")] + survivors
    report = {
      "schemaVersion" => "2", "thresholds" => { "high" => 80, "low" => 60 },
      "projectRoot" => dir,
      "files" => { "lib/order.rb" => { "language" => "ruby", "source" => source, "mutants" => mutants } },
      "testFiles" => { "spec/order_spec.rb" =>
                         { "tests" => [{ "id" => "0", "name" => "./spec/order_spec.rb[1:1]" }] } },
      "saboteur" => { "findings" => { "version" => 1, "survivors" => [
        { "digest" => digest_a, "path" => "lib/order.rb", "line" => 3, "subject" => "Order#total",
          "operator" => "sum_to_map_sum", "original" => "items.sum(&:price)",
          "replacement" => "items.map(&:price).sum", "classification" => "boundary" }
      ], "survivorsTruncated" => 1, "accepted" => [] } }
    }
    File.write(path = File.join(dir, "report.json"), JSON.generate(report))
    path
  end

  it "lists every survivor - including ones the capped findings list omits - with the fields triage needs" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, survivors: [])
      expect(cli("survivors", path).call).to eq(0)
      expect(out.string).to include("lib/order.rb:3", "sum_to_map_sum", "a" * 16, "boundary")
      # b*16 is only in the files section (findings is capped at 10): still listed.
      expect(out.string).to include("b" * 16, "and_to_or")
      expect(out.string).not_to include("Killed")
    end
  end

  it "says so cleanly when the report has no survivors" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, survivors: [])
      File.write(path, JSON.generate(JSON.parse(File.read(path)).tap do |r|
        r["files"]["lib/order.rb"]["mutants"].select! { |_m| false }
      end))
      expect(cli("survivors", path).call).to eq(0)
      expect(out.string).to include("no survivors")
    end
  end

  it "refuses a missing report with exit 2" do
    expect(cli("survivors", "no/such/report.json").call).to eq(2)
    expect(err.string).to include("no/such/report.json")
  end

  it "refuses a malformed report with exit 2" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bad.json")
      File.write(path, "{not json")
      expect(cli("survivors", path).call).to eq(2)
      expect(err.string).to include("bad.json")
    end
  end

  it "filters by operator" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, survivors: [])
      expect(cli("survivors", path, "--operator", "and_to_or").call).to eq(0)
      expect(out.string).to include("b" * 16)
      expect(out.string).not_to include("a" * 16)
    end
  end

  it "shows one survivor: diff, full-digest replay command, ignore template" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, survivors: [])
      expect(cli("survivors", path, "--show", "a" * 16).call).to eq(0)
      expect(out.string).to include("- items.sum(&:price)", "+ items.map(&:price).sum")
      expect(out.string).to include("saboteur run --id #{'a' * 16}")
      expect(out.string).to include(%(i.mutation "#{'a' * 16}")).and include('subject: "Order#total"')
    end
  end

  it "prints the ignore template with a subject placeholder when findings lack the digest" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, survivors: [])
      expect(cli("survivors", path, "--show", "b" * 16).call).to eq(0)
      expect(out.string).to include(%(i.mutation "#{'b' * 16}")).and include("TODO")
      expect(out.string).to include("saboteur run --id #{'b' * 16}")
    end
  end

  describe "CLI parse layer (#520 dogfood survivors)" do
    it "orders by the report's ranked findings with --ranked, by path and digest without" do
      Dir.mktmpdir do |dir|
        path = write_report(dir, survivors: [])
        report = JSON.parse(File.read(path))
        report["saboteur"]["findings"]["survivors"].unshift(
          { "digest" => "b" * 16, "path" => "lib/order.rb", "line" => 3, "subject" => "Order#total",
            "operator" => "and_to_or", "original" => "items", "replacement" => "items",
            "classification" => "boundary" }
        )
        File.write(path, JSON.generate(report))

        expect(cli("survivors", path).call).to eq(0)
        expect(out.string.index("a" * 16)).to be < out.string.index("b" * 16)

        ranked_out = StringIO.new
        expect(described_class.new(["survivors", path, "--ranked"], out: ranked_out, err: err).call).to eq(0)
        expect(ranked_out.string.index("b" * 16)).to be < ranked_out.string.index("a" * 16)
      end
    end

    it "filters survivors by path substring with --file" do
      Dir.mktmpdir do |dir|
        path = write_report(dir, survivors: [])
        expect(cli("survivors", path, "--file", "no-such-file").call).to eq(0)
        expect(out.string).to include("no survivors (file~no-such-file)")
      end
    end

    it "filters survivors by classification with --triage" do
      Dir.mktmpdir do |dir|
        path = write_report(dir, survivors: [])
        expect(cli("survivors", path, "--triage", "boundary").call).to eq(0)
        expect(out.string).to include("a" * 16)
        expect(out.string).not_to include("b" * 16)
      end
    end

    it "refuses a missing report path with the exact usage line and exit 2" do
      expect(cli("survivors").call).to eq(2)
      expect(err.string).to eq("saboteur: survivors expects a report path: saboteur survivors .saboteur/report.json\n")
    end

    it "refuses extra arguments with the exact message and exit 2" do
      Dir.mktmpdir do |dir|
        path = write_report(dir, survivors: [])
        expect(cli("survivors", path, "extra", "args").call).to eq(2)
        expect(err.string).to eq("saboteur: unexpected arguments: extra args\n")
      end
    end

    # OptionParser's officious --help prints the option list - descriptions
    # included - to the real stdout and exits 0.
    it "prints every flag's description on --help" do
      captured = StringIO.new
      $stdout = captured
      begin
        expect { cli("survivors", "--help").call }.to raise_error(SystemExit)
      ensure
        $stdout = STDOUT
      end
      expect(captured.string).to include("Review-priority order",
                                         "Only survivors whose path contains SUBSTR",
                                         "Only survivors of operator NAME",
                                         "Only survivors classified LABEL",
                                         "Diff, replay command and ignore template")
    end

    it "does not leak subcommand flags into the CLI's options" do
      Dir.mktmpdir do |dir|
        path = write_report(dir, survivors: [])
        command = cli("survivors", path, "--triage", "boundary")
        expect(command.call).to eq(0)
        expect(command.options).to eq({})
      end
    end
  end
end
