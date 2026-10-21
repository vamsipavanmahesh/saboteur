# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Survivor confirmation (#1063) runs the scheduler, the coverage map and the
# runner for real: a whole-suite cached run (partial_coverage = use, --all)
# confirms its survivors after the last result. The wiring used to crash the
# run with exit 70 on a private scheduler method; the pass now marks the
# survivor instead, and a skip says why. The unit doubles in
# spec/saboteur/engine/survivor_confirmation_spec.rb pin the marking rules;
# this spec is the proof that the real objects fit together.
RSpec.describe "survivor confirmation (#1063)", :e2e do
  let(:dir) { File.realpath(Dir.mktmpdir("saboteur-e2e-")) }

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
    File.write(File.join(dir, path), text)
  end

  before do
    @e2e_dirs = (@e2e_dirs || []) << dir
    write("config/saboteur.rb", <<~RUBY)
      Saboteur.configure do |c|
        c.include = ["lib/**/*.rb"]
        c.partial_coverage = "use"
      end
    RUBY
    write("lib/answer.rb", <<~RUBY)
      class Answer
        def greeting
          "hello"
        end

        def farewell
          "bye"
        end
      end
    RUBY
    # farewell is only weakly asserted, so its string mutant survives and the
    # confirmation pass has a live survivor to mark.
    write("spec/answer_spec.rb", <<~RUBY)
      require_relative "../lib/answer"

      RSpec.describe Answer do
        it "greets" do
          expect(described_class.new.greeting).to eq("hello")
        end

        it "says farewell" do
          expect(described_class.new.farewell).to be_a(String)
        end
      end
    RUBY
  end

  it "marks the survivor after a real run instead of crashing" do
    run = saboteur(dir, "--all", "--no-color")

    expect(run.status).to eq(1)
    expect(run.err).not_to include("private method")
    expect(run.err).to include("survivor confirmation: 1 unconfirmed(no covering tests)")
  end

  it "says on the run tail when inferred specs skip the confirmation under partial_coverage use" do
    run = saboteur(dir, "--no-color")

    expect(run.status).to eq(1)
    expect(run.err).to include("survivor confirmation skipped: partial_coverage = use applies only to a cached")
  end

  it "stays silent when the skipped run has no live survivor" do
    write("spec/answer_spec.rb", <<~RUBY)
      require_relative "../lib/answer"

      RSpec.describe Answer do
        it "greets" do
          expect(described_class.new.greeting).to eq("hello")
        end

        it "says farewell" do
          expect(described_class.new.farewell).to eq("bye")
        end
      end
    RUBY

    run = saboteur(dir, "--no-color")

    expect(run.status).to eq(0)
    expect(run.err).not_to include("survivor confirmation skipped")
  end
end
