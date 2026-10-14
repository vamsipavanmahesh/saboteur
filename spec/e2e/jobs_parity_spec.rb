# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# A determinism check: every fixture project gives the same status and
# status reason for every mutant with one worker and with three. Slow, because
# each project runs twice.
RSpec.describe "--jobs verdict parity (end to end)", :e2e, :slow do
  %w[people endless].each do |project|
    it "gives identical verdicts for #{project} with --jobs 1 and --jobs 3" do
      dir = copy_fixture(project)
      verdicts = ->(run) { mutants(run).to_h { |m| [m["id"], [m["status"], m["statusReason"]]] } }
      serial = saboteur(dir, "--all", "--jobs", "1")
      parallel = saboteur(dir, "--all", "--jobs", "3")
      expect(serial.status).to be <= 1, other_outcomes(serial)
      one = verdicts.call(serial)
      many = verdicts.call(parallel)
      expect(one).not_to be_empty
      differing = one.keys.union(many.keys).reject { |id| one[id] == many[id] }
      expect(differing.to_h { |id| [id, { jobs1: one[id], jobs3: many[id] }] }).to eq({})
      expect(parallel.status).to eq(serial.status)
    end
  end
end
