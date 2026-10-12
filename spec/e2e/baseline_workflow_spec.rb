# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "opt-in baseline commands", :e2e do
  def command(dir, *args)
    Open3.capture3({ "BUNDLE_GEMFILE" => File.join(E2EHelpers::ROOT, "Gemfile") }, RbConfig.ruby,
                   File.join(E2EHelpers::ROOT, "exe", "saboteur"), "baseline", *args, chdir: dir)
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
      Saboteur.configure do |c|
        c.include = ["lib/probe.rb"]
        c.rspec_args = ["spec/probe_spec.rb"]
        c.max_mutants_per_method = 1000
      end
    RUBY
    out, err, status = command(dir, "propose", "--baseline", "baseline.json", "--proposal", "proposal.json")
    expect(status.exitstatus).to eq(0), out + err
    expect(JSON.parse(out).fetch("state")).to eq("proposal")
    proposal_path = File.join(dir, "proposal.json")
    proposal = JSON.parse(File.read(proposal_path))
    expect(proposal.fetch("execution").fetch("complete")).to be(true)
    expect(proposal.fetch("document").fetch("accepted")).not_to be_empty
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
    source = File.join(dir, "lib", "probe.rb")
    File.write(source, File.read(source).sub("    1", "    2"))
    out, err, status = command(dir, "check", "--baseline", "baseline.json")
    expect(status.exitstatus).to eq(1), out + err
    expect(JSON.parse(out).fetch("state")).to eq("review_required")
  end
end
