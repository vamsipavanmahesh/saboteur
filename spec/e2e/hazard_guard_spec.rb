# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "hazard guard and canary (issue #102)", :e2e do
  let(:dir) { copy_fixture("danger") }

  it "suppresses mutants inside the destructive call and leaves the tree intact" do
    run = saboteur(dir)
    expect(run.status).to eq(0)
    expect(run.out).to include("hazardous mutations suppressed")
    expect(File).to exist(File.join(dir, "SENTINEL.txt"))
    expect(File).to exist(File.join(dir, "lib", "builder.rb"))
    expect(File).to exist(File.join(dir, "spec", "builder_spec.rb"))
    expect(File).to exist(File.join(dir, "config", "saboteur.rb"))
  end

  # The fixture lives under the system temp dir, which the sandbox always
  # grants, so the destructive mutant really deletes - tracked files and
  # the run's own log. The hazard report must win over the log's absence:
  it "suppresses mutants when send names the destructive call with a literal selector (#240)" do
    send_dir = copy_fixture("danger_send")
    run = saboteur(send_dir)
    expect(run.status).to eq(0)
    expect(run.out).to include("hazardous mutations suppressed")
    expect(File).to exist(File.join(send_dir, "lib", "dispatcher.rb"))
  end

  # exit 3, the canary naming the mutant as the likely cause, and never
  # the "killing test also fails" mislabel (#234).
  it "aborts with exit 3, the canary naming the culprit, when hazardous mutants are allowed" do
    run = saboteur(dir, "--allow-hazardous")
    expect(run.status).to eq(3)
    expect(run.err).to include("canary")
    expect(run.err).to match(/[0-9a-f]{16}/)
    expect(run.err).not_to include("killing test")
  end

  it "fails fast in parallel: the hazard report aborts the run, not just the subject" do
    run = saboteur(dir, "--allow-hazardous", "--jobs", "2")
    expect(run.status).to eq(3)
    expect(run.err).to include("canary")
    expect(run.err).to match(/[0-9a-f]{16}/)
    expect(run.err).not_to include("killing test")
  end

  # The logloss fixture's unchanged code deletes only the project's own
  # .saboteur/trash: a literal mutation redirects the deletion onto the
  # tool's cache, so a vanished run file is the mutant's doing alone. An
  # earlier subject's mutants die normally, so the aborted run still shows
  # real kills (the dot line) alongside the tool error - exit 3, the mutant
  # named, and never the "killing test also fails" mislabel (#234).
  it "aborts with a tool error when only the tool's own files vanish" do
    run = saboteur(copy_fixture("logloss"), "--allow-hazardous")
    expect(run.status).to eq(3)
    expect(run.err).to include("vanished mid-run")
    expect(run.err).to match(/[0-9a-f]{16}/)
    expect(run.err).to match(%r{^\.+ {2}\d+/\d+ })
    expect(run.err).not_to include("killing test")
  end

  # The treewipe fixture's mid-subject literal mutant deletes lib/ (tracked)
  # but spares the run's own log: only a per-mutant canary probe names the
  # culprit - the per-subject check would blame the subject's last mutant
  # (#235).
  it "names the culprit mutant, not the last mutant of the subject" do
    run = saboteur(copy_fixture("treewipe"), "--allow-hazardous")
    culprit = fixture_mutation_digest(
      File.join(__dir__, "..", "fixtures", "projects", "treewipe", "lib", "sweeper.rb"),
      "Sweeper#sweep", '"generated"'
    )
    expect(run.status).to eq(3)
    expect(run.err).to include("canary")
    expect(run.err).to include("just ran, #{culprit}")
    expect(run.err).not_to include("most recent mutant")
    expect(run.err).not_to include("killing test")
  end

  it "aborts the same way in parallel, with kills still landing alongside" do
    run = saboteur(copy_fixture("logloss"), "--allow-hazardous", "--jobs", "2")
    expect(run.status).to eq(3)
    expect(run.err).to include("vanished mid-run")
    expect(run.err).to match(/[0-9a-f]{16}/)
    expect(run.err).to match(%r{^\.+ {2}\d+/\d+ })
    expect(run.err).not_to include("killing test")
  end

  # The digest a real run prints for one mutation of a fixture subject:
  # content-based, so the source fixture and its copied run agree.
  def fixture_mutation_digest(path, subject_id, original)
    path = File.expand_path(path)
    subject = Saboteur::SubjectFinder.new.call(path).subjects.find { |s| s.id == subject_id }
    mutation = Saboteur::MutationSource::Builtin.new(arid: [], operators: [], exclude_operators: [])
                                                .mutations_for(subject).find do |m|
      m.edits.any? do |edit|
        subject.file_source.byteslice(edit.start_byte, edit.end_byte - edit.start_byte) == original
      end
    end
    mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
  end
end
