# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# --test-command (#140): each mutant is written to the real file and the
# given command decides the verdict by exit status. No boot, no coverage,
# serial; the tree comes back untouched.
RSpec.describe "--test-command", :e2e do
  let(:dir) { copy_fixture("people") }

  # Kills mutants that flip adult?, survives everything else.
  def check_command
    check = 'require "people"; exit(People::Person.new(20).adult? ? 0 : 1)'
    "#{RbConfig.ruby} -Ilib -e '#{check}'"
  end

  it "kills by exit status, reports survivors, and restores the tree" do
    original = File.read(File.join(dir, "lib", "people.rb"))
    run = saboteur(dir, "--test-command", check_command)

    expect(run.status).to eq(1)
    expect(run.err).to include("external test command", "serial, no coverage, unsandboxed")
    statuses = run.json.fetch("mutants", run.json["files"].values.flat_map { |f| f["mutants"] }).map { |m| m["status"] }
    expect(statuses).to include("Survived", "Killed")
    expect(File.read(File.join(dir, "lib", "people.rb"))).to eq(original)
    expect(run.out).not_to include("ruby executes only the first")
  end

  # ruby executes only the FIRST script named on its command line; the
  # rest silently never run and their mutants inflate the survivors (#611).
  it "warns when one ruby is handed several test files" do
    File.write(File.join(dir, "a_check_test.rb"), "exit 0\n")
    File.write(File.join(dir, "b_check_test.rb"), "exit 0\n")
    run = saboteur(dir, "--test-command", "#{RbConfig.ruby} -Ilib a_check_test.rb b_check_test.rb")
    expect(run.out).to include("ruby executes only the first")
  end

  # #641: a command that never exercises a subject leaves its mutants
  # surviving with no coverage map to explain why; the report names the gap
  # per subject instead of reading as real survivors.
  it "names subjects the command may never exercise when everything survives" do
    run = saboteur(dir, "--test-command", "true")
    expect(run.out).to include("no coverage map under --test-command; " \
                               "check your command exercises lib/people.rb")
  end

  # The unchanged-tree control: one neutral preflight runs the command
  # before any mutant exists, so a command that fails without the mutant
  # fails the whole run up front with its own exit status (exit 5, #305).
  it "refuses to run when the command fails on the unchanged tree" do
    run = saboteur(dir, "--test-command", "false")
    expect(run.status).to eq(5)
    expect(run.err).to include("the test command fails on the unchanged tree (exit 1)")
  end
end
