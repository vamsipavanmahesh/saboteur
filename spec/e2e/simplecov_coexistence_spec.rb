# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Models the README "Know the limits" advice: a suite that starts SimpleCov
# anyway. saboteur needs Ruby's Coverage for itself, so its boot turns
# SimpleCov.start into a no-op with a notice and the run still measures
# kills. (lib/saboteur/engine/boot.rb, SimpleCovWatch/SimpleCovOff.)
RSpec.describe "a suite that starts SimpleCov (end to end)", :e2e do
  it "ignores SimpleCov.start, says so, and still scores the run" do
    dir = copy_fixture("people")
    person = File.join(dir, "spec", "person_spec.rb")
    File.write(person, "require \"simplecov\"\nSimpleCov.start\n#{File.read(person)}")
    run = saboteur(dir)
    expect(run.err).to include("SimpleCov.start ignored for this run")
    # The people fixture has survivors by design; exit 1 proves the run
    # measured kills and survivors with Ruby's Coverage, SimpleCov no-oped.
    expect(run.status).to eq(1), run.err
    expect(run.out).to include("Score:")
  end
end
