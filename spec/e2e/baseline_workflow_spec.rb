# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "opt-in baseline commands", :e2e do
  def command(dir, *args)
    Open3.capture3({ "BUNDLE_GEMFILE" => File.join(E2EHelpers::ROOT, "Gemfile") }, RbConfig.ruby,
                   File.join(E2EHelpers::ROOT, "exe", "saboteur"), "baseline", *args, chdir: dir)
  end

  def reject_nested(dir, path, destination, record, previous: nil)
    original = File.exist?(destination) ? File.binread(destination) : nil
    evidence = Dir.glob(File.join(dir, ".saboteur", "baseline-evidence", "*.json"))
    [nil, { "accepted" => nil }, { "accepted" => [nil] }, { "accepted" => [3] }].each do |bad|
      edited = JSON.parse(JSON.generate(record))
      edited["document"] = bad
      File.write(path, JSON.generate(edited))
      args = ["accept", "--baseline", destination, "--proposal", path]
      args += ["--previous", previous] if previous
      rejected_command(dir, args)
      expect(Dir.glob(File.join(dir, ".saboteur", "baseline-evidence", "*.json"))).to eq(evidence)
      expect(File.exist?(destination) ? File.binread(destination) : nil).to eq(original)
    end
    File.write(path, JSON.generate(record))
  end

  def rejected_command(dir, args)
    out, err, status = command(dir, *args)
    expect(status.exitstatus).to eq(2), out + err
    expect(out).to eq("")
    expect(err).to include("document or acceptance shape")
    expect(err).not_to include("NoMethodError", "from ")
  end

  it "proposes, accepts and checks fresh real evidence without changing ordinary run semantics" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "lib", "probe.rb"), "class BaselineProbe\n  def value\n    1\n  end\nend\n")
    File.write(File.join(dir, "spec", "probe_spec.rb"), <<~RUBY)
      require_relative "../lib/probe"
      RSpec.describe BaselineProbe do
        it("runs the value") { expect(BaselineProbe.new.value).not_to be_nil }
      end
    RUBY
    File.write(File.join(dir, "config", "saboteur.rb"), <<~RUBY)
      puts "config diagnostic"
      Saboteur.configure do |c|
        c.include = ["lib/probe.rb"]
        c.rspec_args = ["spec/probe_spec.rb"]
        c.max_mutants_per_method = 1000
        c.require = ["boot.rb"]
        c.hooks = ["hooks.rb"]
      end
    RUBY
    File.write(File.join(dir, "boot.rb"), 'puts "boot diagnostic"')
    File.write(File.join(dir, "hooks.rb"), 'puts "hook diagnostic"')
    out, err, status = command(dir, "propose", "--baseline", "baseline.json", "--proposal", "proposal.json",
                               "--format", "json")
    expect(status.exitstatus).to eq(0), out + err
    expect(JSON.parse(out).fetch("state")).to eq("proposal")
    expect(err).to include("config diagnostic", "boot diagnostic", "hook diagnostic")
    proposal_path = File.join(dir, "proposal.json")
    proposal = JSON.parse(File.read(proposal_path, encoding: "UTF-8"))
    expect(proposal.fetch("execution").fetch("complete")).to be(true)
    expect(proposal.fetch("document").fetch("accepted")).not_to be_empty
    reject_nested(dir, proposal_path, File.join(dir, "baseline.json"), proposal)
    out, err, status = command(dir, "accept", "--baseline", "baseline.json", "--proposal", "proposal.json")
    expect(status.exitstatus).to eq(2), out + err
    expect(err).to include("reason")
    proposal.fetch("document").fetch("accepted").each { |entry| entry["reason"] = "reviewed fixture gap" }
    File.write(proposal_path, JSON.generate(proposal))
    out, err, status = command(dir, "accept", "--baseline", "baseline.json", "--proposal", "proposal.json")
    expect(status.exitstatus).to eq(0), out + err
    expect(JSON.parse(out).fetch("state")).to eq("accepted")
    out, err, status = command(dir, "check", "--baseline", "baseline.json")
    expect(status.exitstatus).to eq(0), out + err
    checked = JSON.parse(out)
    expect(checked.fetch("state")).to eq("clean")
    expect(checked.fetch("categories").fetch("accepted")).not_to be_empty
    out, err, status = command(dir, "check", "--baseline", "baseline.json", "--epsilon", "0")
    expect(status.exitstatus).to eq(0), out + err
    expect(JSON.parse(out).fetch("score")).to include("drop" => 0.0, "epsilon" => 0.0, "exceeded" => false)
    expect(checked).not_to have_key("score")
    baseline_path = File.join(dir, "baseline.json")
    previous = Digest::SHA256.file(baseline_path).hexdigest
    out, err, status = command(dir, "propose", "--baseline", "baseline.json", "--proposal", "replacement.json",
                               "--previous", previous, "--format", "json")
    expect(status.exitstatus).to eq(0), out + err
    replacement = File.join(dir, "replacement.json")
    revised = JSON.parse(File.read(replacement, encoding: "UTF-8"))
    revised.fetch("document").fetch("accepted").each { |entry| entry["reason"] = "reviewed replacement" }
    File.write(replacement, JSON.generate(revised))
    reject_nested(dir, replacement, baseline_path, revised, previous: previous)
    out, err, status = command(dir, "accept", "--baseline", "baseline.json", "--proposal", "replacement.json")
    expect(status.exitstatus).to eq(2), out + err
    expect(Digest::SHA256.file(baseline_path).hexdigest).to eq(previous)
    out, err, status = command(dir, "accept", "--baseline", "baseline.json", "--proposal", "replacement.json",
                               "--previous", previous)
    expect(status.exitstatus).to eq(0), out + err
    source = File.join(dir, "lib", "probe.rb")
    File.write(source, File.read(source).sub("    1", "    2"))
    out, err, status = command(dir, "check", "--baseline", "baseline.json")
    expect(status.exitstatus).to eq(1), out + err
    expect(JSON.parse(out).fetch("state")).to eq("review_required")
  end

  def probe_fixture(dir, methods: "  def value\n    1\n  end\n  def other\n    2\n  end", tested: "value",
                    extra_config: "")
    File.write(File.join(dir, "lib", "probe.rb"), "class BaselineProbe\n#{methods}\nend\n")
    File.write(File.join(dir, "spec", "probe_spec.rb"), <<~RUBY)
      require_relative "../lib/probe"
      RSpec.describe BaselineProbe do
        it("runs #{tested}") { expect(BaselineProbe.new.#{tested}).to eq(1) }
      end
    RUBY
    File.write(File.join(dir, "config", "saboteur.rb"), <<~RUBY)
      Saboteur.configure do |c|
        c.include = ["lib/probe.rb"]
        c.rspec_args = ["spec/probe_spec.rb"]
        #{extra_config}
      end
    RUBY
  end

  it "proposes over an untested subject, names the gap, and the accepted baseline checks clean" do
    dir = copy_fixture("people")
    probe_fixture(dir)
    out, err, status = command(dir, "propose", "--baseline", "baseline.json", "--proposal", "proposal.json")
    expect(status.exitstatus).to eq(0), out + err
    expect(out).to include("baseline proposal written:", "matched mutants:",
                           "proposed with 1 untested subjects:", "BaselineProbe#other",
                           "the baseline cannot speak for them", "saboteur baseline accept")
    expect { JSON.parse(out) }.to raise_error(JSON::ParserError)
    proposal = JSON.parse(File.read(File.join(dir, "proposal.json"), encoding: "UTF-8"))
    execution = proposal.fetch("execution")
    expect(execution.fetch("proposable")).to be(true)
    expect(execution.fetch("complete")).to be(false)
    expect(execution.fetch("blockers")).to eq([])
    expect(execution.fetch("gaps")).to eq(["subject_skipped:BaselineProbe#other:no coverage"])
    expect(proposal.fetch("document").fetch("metadata").fetch("proposable")).to be(true)
    proposal.fetch("document").fetch("accepted").each { |entry| entry["reason"] = "reviewed fixture gap" }
    File.write(File.join(dir, "proposal.json"), JSON.generate(proposal))
    out, err, status = command(dir, "accept", "--baseline", "baseline.json", "--proposal", "proposal.json")
    expect(status.exitstatus).to eq(0), out + err
    out, err, status = command(dir, "check", "--baseline", "baseline.json")
    expect(status.exitstatus).to eq(0), out + err
    expect(JSON.parse(out).fetch("state")).to eq("clean")
  end

  it "prints terminal output for a fully tested --subject proposal" do
    dir = copy_fixture("people")
    probe_fixture(dir, methods: "  def value\n    1\n  end")
    out, err, status = command(dir, "propose", "--baseline", "baseline.json", "--proposal", "proposal.json",
                               "--subject", "BaselineProbe#value")
    expect(status.exitstatus).to eq(0), out + err
    expect(out).to include("baseline proposal written:", "matched mutants:", "next step:")
    expect(out).not_to include("untested subjects")
    expect { JSON.parse(out) }.to raise_error(JSON::ParserError)
  end

  it "refuses with the blocking issues listed before the sentence when the unchanged suite lacks two stable passes" do
    dir = copy_fixture("people")
    probe_fixture(dir, methods: "  def value\n    1\n  end", extra_config: "c.baseline_passes = 1")
    out, err, status = command(dir, "propose", "--baseline", "baseline.json", "--proposal", "proposal.json")
    expect(status.exitstatus).to eq(3), out + err
    blocker = err.index("saboteur: baseline proposal blocker: unchanged_suite_incomplete")
    refusal = err.index("saboteur: baseline proposal needs a proposable run")
    expect(blocker).not_to be_nil, err
    expect(refusal).not_to be_nil, err
    expect(blocker).to be < refusal
    expect(File.exist?(File.join(dir, "proposal.json"))).to be(false)
  end
end
