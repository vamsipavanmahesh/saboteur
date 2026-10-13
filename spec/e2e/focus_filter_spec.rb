# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "saboteur run with a focus filter in the suite (end to end)", :e2e do
  let(:dir) { copy_fixture("people") }

  def focus_the_adult_example
    File.write(File.join(dir, ".rspec"), "--require ./spec/focus_helper.rb\n")
    File.write(File.join(dir, "spec", "focus_helper.rb"), <<~RUBY)
      RSpec.configure { |config| config.filter_run_when_matching :focus }
    RUBY
    path = File.join(dir, "spec", "person_spec.rb")
    File.write(path, File.read(path).sub('it "is an adult at 19"', 'fit "is an adult at 19"'))
  end

  it "runs the whole suite when nothing is focused" do
    File.write(File.join(dir, ".rspec"), "--require ./spec/focus_helper.rb\n")
    File.write(File.join(dir, "spec", "focus_helper.rb"),
               "RSpec.configure { |config| config.filter_run_when_matching :focus }\n")
    run = saboteur(dir, "lib/people.rb", "--test", "spec/person_spec.rb")
    expect(run.err).not_to include("focus")
    expect(mutants(run).map { |m| m["status"] }).to include("Killed")
  end

  it "exits 2 and names the focused example instead of scoring a narrowed run" do
    focus_the_adult_example
    run = saboteur(dir, "lib/people.rb", "--test", "spec/person_spec.rb")
    expect(run.status).to eq(2), run.err
    expect(run.err).to include("focus filter")
    expect(run.err).to match(%r{spec/person_spec\.rb:\d+})
    expect(run.err).to include("--allow-focus")
    expect(run.json).to be_nil
  end

  it "runs the narrowed suite when --allow-focus is given" do
    focus_the_adult_example
    run = saboteur(dir, "lib/people.rb", "--test", "spec/person_spec.rb", "--allow-focus")
    expect(run.status).not_to eq(2), run.err
    expect(run.json).not_to be_nil
  end

  it "does not refuse a run narrowed on purpose with --tag in rspec_args" do
    focus_the_adult_example
    File.write(File.join(dir, ".rspec"), "--require ./spec/focus_helper.rb\n--tag focus\n")
    run = saboteur(dir, "lib/people.rb", "--test", "spec/person_spec.rb")
    expect(run.err).not_to include("focus filter")
    expect(run.json).not_to be_nil
  end
end
