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
                      classification: "missing_test", covered: ["0"]),
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
          "replacement" => "items.map(&:price).sum", "classification" => "missing_test" }
      ], "survivorsTruncated" => 1, "accepted" => [] } }
    }
    File.write(path = File.join(dir, "report.json"), JSON.generate(report))
    path
  end

  it "lists every survivor - including ones the capped findings list omits - with the fields triage needs" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, survivors: [])
      expect(cli("survivors", path).call).to eq(0)
      expect(out.string).to include("lib/order.rb:3", "sum_to_map_sum", "a" * 16, "missing_test")
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

  it "fills the ignore subject from the files section when findings lack the digest (#1181)" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, survivors: [])
      report = JSON.parse(File.read(path))
      report["files"]["lib/order.rb"]["mutants"].each { |m| m["subject"] = "Order#total" }
      File.write(path, JSON.generate(report))
      expect(cli("survivors", path, "--show", "b" * 16).call).to eq(0)
      expect(out.string).to include(%(i.mutation "#{'b' * 16}")).and include('subject: "Order#total"')
      expect(out.string).not_to include("TODO")
    end
  end

  it "shows the classification, why-it-matters, covering tests and hint like the terminal (#1183)" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, survivors: [])
      expect(cli("survivors", path, "--show", "a" * 16).call).to eq(0)
      expect(out.string).to include("classification: missing_test - ",
                                    "the covering specs pass without pinning this change")
      expect(out.string).to include("why it matters:")
      expect(out.string).to include("covered by ./spec/order_spec.rb[1:1] - ran, still passed")
    end
  end

  it "omits the classification and hint lines for an unclassified survivor" do
    Dir.mktmpdir do |dir|
      path = write_report(dir, survivors: [])
      expect(cli("survivors", path, "--show", "b" * 16).call).to eq(0)
      expect(out.string).not_to include("classification:", "hint:")
    end
  end

  describe "detail lines (#1194 dogfood survivors)" do
    it "names the first covering test and counts the rest" do
      Dir.mktmpdir do |dir|
        path = write_report(dir, survivors: [])
        report = JSON.parse(File.read(path))
        report["files"]["lib/order.rb"]["mutants"].first["coveredBy"] = %w[0 1 2]
        report["testFiles"]["spec/order_spec.rb"]["tests"] +=
          [{ "id" => "1", "name" => "./spec/order_spec.rb[1:2]" },
           { "id" => "2", "name" => "./spec/order_spec.rb[1:3]" }]
        File.write(path, JSON.generate(report))
        report["files"]["lib/order.rb"]["mutants"].last["coveredBy"] = %w[0 1]
        File.write(path, JSON.generate(report))
        expect(cli("survivors", path, "--show", "a" * 16).call).to eq(0)
        expect(out.string).to include("covered by ./spec/order_spec.rb[1:1] (+2 more) - ran, still passed")
        expect(cli("survivors", path, "--show", "b" * 16).call).to eq(0)
        expect(out.string).to include("covered by ./spec/order_spec.rb[1:1] (+1 more) - ran, still passed")
      end
    end

    it "prints the hint for a hint-bearing classification" do
      Dir.mktmpdir do |dir|
        path = write_report(dir, survivors: [])
        report = JSON.parse(File.read(path))
        report["files"]["lib/order.rb"]["mutants"].first
                                                  .merge!("mutatorName" => "comparison", "classification" => "arid")
        File.write(path, JSON.generate(report))
        expect(cli("survivors", path, "--show", "a" * 16).call).to eq(0)
        expect(out.string).to include("hint: try an example at the boundary: equal values, or values one apart")
      end
    end

    it "prints a bare classification line for a label with no reason" do
      Dir.mktmpdir do |dir|
        path = write_report(dir, survivors: [])
        report = JSON.parse(File.read(path))
        report["files"]["lib/order.rb"]["mutants"].first["classification"] = "assertion_gap"
        File.write(path, JSON.generate(report))
        expect(cli("survivors", path, "--show", "a" * 16).call).to eq(0)
        expect(out.string).to include("classification: assertion_gap\n")
        expect(out.string).not_to include("assertion_gap -")
      end
    end

    it "tolerates a testFiles entry without a tests list" do
      Dir.mktmpdir do |dir|
        path = write_report(dir, survivors: [])
        report = JSON.parse(File.read(path))
        report["testFiles"][""] = {}
        File.write(path, JSON.generate(report))
        expect(cli("survivors", path, "--show", "a" * 16).call).to eq(0)
        expect(out.string).to include("covered by ./spec/order_spec.rb[1:1] - ran, still passed")
      end
    end

    it "returns empty line arrays from the detail helpers when nothing applies" do
      browser = Saboteur::CLI::SurvivorsBrowser.new({})
      expect(browser.send(:classification_line, nil)).to eq([])
      expect(browser.send(:covered_line, { covered: [] })).to eq([])
      expect(browser.send(:hint_line, { operator: "comparison" }, nil)).to eq([])
    end

    it "memoizes the test-name index" do
      browser = Saboteur::CLI::SurvivorsBrowser.new({ "testFiles" => {} })
      expect(browser.send(:test_names)).to equal(browser.send(:test_names))
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
            "classification" => "missing_test" }
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
        expect(cli("survivors", path, "--triage", "missing_test").call).to eq(0)
        expect(out.string).to include("a" * 16)
        expect(out.string).not_to include("b" * 16)
      end
    end

    it "names a missing explicit report without the run-first hint" do
      expect(cli("survivors", "nope.json").call).to eq(2)
      expect(err.string).to eq("saboteur: report not found: nope.json\n")
    end

    it "shows a unique digest prefix, refuses an ambiguous one with every match, and an unknown one" do
      Dir.mktmpdir do |dir|
        close = mutant(id: "#{'a' * 8}#{'c' * 8}", operator: "and_to_or", line: 3, status: "Survived")
        path = write_report(dir, survivors: [close])
        expect(cli("survivors", path, "--show", "aaaaaaaac").call).to eq(0)
        expect(out.string).to include("#{'a' * 8}#{'c' * 8}")
        expect(cli("survivors", path, "--show", "aaaa").call).to eq(2)
        expect(err.string).to eq("saboteur: digest prefix aaaa matches 2 survivors: " \
                                 "#{'a' * 16}, #{'a' * 8}#{'c' * 8}; use more characters\n")
        err.truncate(0)
        err.rewind
        expect(cli("survivors", path, "--show", "zzzz").call).to eq(2)
        expect(err.string).to eq("saboteur: no survivor with digest zzzz in this report\n")
      end
    end

    it "reads .saboteur/report.json when no path is given, and says so when it is absent" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect(cli("survivors").call).to eq(2)
          expect(err.string).to eq("saboteur: report not found: .saboteur/report.json; " \
                                   "run saboteur first, or pass a report path\n")
          FileUtils.mkdir_p(".saboteur")
          FileUtils.cp(write_report(dir, survivors: []), ".saboteur/report.json")
          expect(cli("survivors").call).to eq(0)
          expect(out.string).to include("aaaaaaaaaaaaaaaa")
        end
      end
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
        command = cli("survivors", path, "--triage", "missing_test")
        expect(command.call).to eq(0)
        expect(command.options).to eq({})
      end
    end
  end
end
