# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# The opt-in macOS sandbox end to end (exercised by the saboteur-mac
# runners, skipped elsewhere): with c.sandbox = "seatbelt" a real run
# confines its children, the inherited child logs still land, and the
# verdicts are normal - the probe found Seatbelt enforcing, so no
# degrade note. Fixture copies live under the system temp dir, which the
# sandbox always grants, so this asserts wiring, not write denial; the
# denial half is the child-confinement spec in execution/seatbelt_spec.rb.
RSpec.describe "macOS Seatbelt sandbox", :e2e do
  before { skip "Seatbelt unavailable" unless Saboteur::Execution::Seatbelt.available? }

  it "runs confined children end to end with the logs intact" do
    dir = copy_fixture("people")
    config = File.join(dir, "config", "saboteur.rb")
    # Insert inside the configure block: appended after its end, the line
    # would be top-level code and ConfigFile.load would raise.
    File.write(config, File.read(config).sub(/\nend\s*\z/, "\n  c.sandbox = \"seatbelt\"\nend\n"))
    run = saboteur(dir)
    expect(run.status).to eq(0)
    expect(run.out).not_to include("hazard guard and canary only")
    expect(File).to exist(File.join(dir, ".saboteur", "report.json"))
  end
end
