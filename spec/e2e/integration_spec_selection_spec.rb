# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Issue #1159, scenario 1: a PR whose real tests live in an integration
# spec. No spec is named after lib/ledger.rb, so name inference finds
# nothing; the run must select the covering integration spec through the
# coverage map, run only it, and still kill the mutants.
RSpec.describe "--since with tests only in an integration spec", :e2e do
  def commit(dir)
    system("git", "init", "-q", dir, exception: true)
    system("git", "-C", dir, "add", ".", exception: true)
    system("git", "-C", dir, "-c", "user.name=t", "-c", "user.email=t@example.com",
           "commit", "-q", "-m", "base", exception: true)
  end

  it "runs only the integration spec and kills the mutants" do
    dir = copy_fixture("integrated")
    commit(dir)
    # The PR: the fee changes, and its integration spec follows.
    lib = File.join(dir, "lib", "ledger.rb")
    File.write(lib, File.read(lib).sub("amount * 2", "amount * 3"))
    flow = File.join(dir, "spec", "integration", "payment_flow_spec.rb")
    File.write(flow, File.read(flow).sub("eq(4)", "eq(6)").sub("eq(10)", "eq(15)"))

    run = saboteur(dir, "--since", "HEAD", env: { "SABOTEUR_E2E_TRACE" => "1" })
    expect(run.status).to eq(0), other_outcomes(run)
    expect(mutants(run).map { |m| m["status"] }.uniq).to eq(["Killed"])

    loaded = File.read(File.join(dir, "tmp", "loaded_specs.log")).lines.map(&:chomp)
    expect(loaded.uniq).to eq(["payment_flow_spec.rb"])
  end
end
