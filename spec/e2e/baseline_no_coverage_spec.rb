# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# #1287: a mutant on a line no test runs, inside a tested subject, used to
# block `baseline propose` as an unexecuted mutant. It is a gap the proposal
# lists, like an untested subject, and a later check does not call it an error.
RSpec.describe "baseline over mutants on lines no test runs", :e2e do
  let(:dir) { copy_fixture("people") }

  def command(*args)
    Open3.capture3({ "BUNDLE_GEMFILE" => File.join(E2EHelpers::ROOT, "Gemfile") }, RbConfig.ruby,
                   File.join(E2EHelpers::ROOT, "exe", "saboteur"), "baseline", *args, chdir: dir)
  end

  before do
    FileUtils.mkdir_p(File.join(dir, "lib", "ledger"))
    File.write(File.join(dir, "lib", "ledger", "transfer.rb"), <<~RUBY)
      module Ledger
        class Transfer
          def safe_ratio(part, whole)
            part / whole
          rescue ZeroDivisionError
            0
          end
        end
      end
    RUBY
    FileUtils.mkdir_p(File.join(dir, "spec", "ledger"))
    File.write(File.join(dir, "spec", "ledger", "transfer_spec.rb"), <<~RUBY)
      require_relative "../../lib/ledger/transfer"

      RSpec.describe Ledger::Transfer do
        it("divides") { expect(described_class.new.safe_ratio(10, 5)).to eq(2) }
      end
    RUBY
  end

  def propose
    command("propose", "--subject", "Ledger::Transfer", "--baseline", "baseline.json", "--proposal", "proposal.json",
            "--format", "json")
  end

  it "proposes over the uncovered rescue line, lists it as a gap and prints no unexecuted blocker" do
    out, err, status = propose

    expect(status.exitstatus).to eq(0), out + err
    expect(err).not_to include("unexecuted:")
    expect(JSON.parse(out).fetch("gaps")).to all(start_with("no_coverage:"))
    expect(JSON.parse(out).fetch("gaps")).not_to be_empty
  end

  it "accepts the proposal and checks clean, with the gap neither an error nor drift" do
    out, err, status = propose
    expect(status.exitstatus).to eq(0), out + err
    path = File.join(dir, "proposal.json")
    proposal = JSON.parse(File.read(path, encoding: "UTF-8"))
    proposal.fetch("document").fetch("accepted").each { |entry| entry["reason"] = "reviewed gap" }
    File.write(path, JSON.generate(proposal))
    out, err, status = command("accept", "--subject", "Ledger::Transfer", "--baseline", "baseline.json",
                               "--proposal", "proposal.json")
    expect(status.exitstatus).to eq(0), out + err

    out, err, status = command("check", "--subject", "Ledger::Transfer", "--baseline", "baseline.json")

    expect(status.exitstatus).to eq(0), out + err
    checked = JSON.parse(out)
    expect(checked.fetch("state")).to eq("clean")
    expect(checked.fetch("categories").fetch("errors")).to be_empty
  end

  it "still checks clean once a later spec covers the rescue line" do
    out, err, status = propose
    expect(status.exitstatus).to eq(0), out + err
    path = File.join(dir, "proposal.json")
    proposal = JSON.parse(File.read(path, encoding: "UTF-8"))
    proposal.fetch("document").fetch("accepted").each { |entry| entry["reason"] = "reviewed gap" }
    File.write(path, JSON.generate(proposal))
    command("accept", "--subject", "Ledger::Transfer", "--baseline", "baseline.json", "--proposal", "proposal.json")
    File.write(File.join(dir, "spec", "ledger", "transfer_spec.rb"), <<~RUBY)
      require_relative "../../lib/ledger/transfer"

      RSpec.describe Ledger::Transfer do
        it("divides") { expect(described_class.new.safe_ratio(10, 5)).to eq(2) }
        it("answers zero for a zero whole") { expect(described_class.new.safe_ratio(1, 0)).to eq(0) }
      end
    RUBY

    out, err, status = command("check", "--subject", "Ledger::Transfer", "--baseline", "baseline.json")

    expect(status.exitstatus).to eq(0), out + err
    expect(JSON.parse(out).fetch("state")).to eq("clean")
  end
end
