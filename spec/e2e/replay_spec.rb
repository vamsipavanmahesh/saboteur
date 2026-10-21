# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "single-mutant replay", :e2e do
  let(:dir) { copy_fixture("people") }

  it "replays a fine mutant despite caps and incremental reuse, with the same selected tests" do
    original = saboteur(dir, "--all", "--subject", "People::Person#adult?")
    mutant = mutants(original).find { |item| !item["mutatorName"].start_with?("body_") }
    expect(mutant).not_to be_nil
    File.open(File.join(dir, "config", "saboteur.rb"), "a") do |file|
      file.puts "Saboteur.configure { |c| c.max_mutants_per_method = 1 }"
    end
    replay = saboteur(dir, "--all", "--id", mutant.fetch("id"), "--seed", "1", "--incremental", "--jobs", "2")
    expect(mutants(replay).size).to eq(1)
    actual = mutants(replay).first
    expect(actual.values_at("id", "status")).to eq(mutant.values_at("id", "status"))
    expect(test_names(replay, actual.fetch("coveredBy"))).to eq(test_names(original, mutant.fetch("coveredBy")))
    expect(replay.out).not_to include("reused")
    expect(File).not_to exist(File.join(dir, ".saboteur", "results.json"))
  end

  it "reports a missing digest without building coverage or writing a report" do
    replay = saboteur(dir, "--all", "--id", "0" * 16)
    expect(replay.status).to eq(2)
    expect(replay.err).to include("not found")
    expect(replay.json).to be_nil
    expect(replay.err).not_to include("building coverage map")
  end

  it "rejects a digest prefix" do
    replay = saboteur(dir, "--all", "--id", "abcd")
    expect(replay.status).to eq(2)
    expect(replay.err).to include("16 lowercase hexadecimal")
  end
end

RSpec.describe "replay bypasses", :e2e do
  let(:dir) { copy_fixture("people") }

  it "executes fresh with a real verdict cache and does not change it" do
    original = saboteur(dir, "--all", "--subject", "People::Person#adult?", "--incremental")
    mutant = mutants(original).find { |item| item["status"] == "Killed" }
    path = File.join(dir, ".saboteur", "results.json")
    before = File.binread(path)
    expect(JSON.parse(before).to_s).to include(mutant.fetch("id"))
    replay = saboteur(dir, "--all", "--id", mutant.fetch("id"), "--incremental")
    expect(mutants(replay).first.fetch("status")).to eq("Killed")
    expect(replay.out).not_to include("reused")
    expect(File.binread(path)).to eq(before)
  end

  it "runs a fine mutant after a coarse survivor and does not suppress an accepted survivor" do
    File.open(File.join(dir, "lib", "people.rb"), "a") do |file|
      file.puts "class Loose; def value; 123; end; end"
    end
    File.write(File.join(dir, "spec", "loose_spec.rb"), <<~RUBY)
      require_relative "../lib/people"
      RSpec.describe Loose do
        it("calls value") { Loose.new.value }
      end
    RUBY
    original = saboteur(dir, "--all", "--subject", "Loose#value")
    expect(original.json).not_to be_nil, original.err
    mutant = mutants(original).find { |item| !item["mutatorName"].start_with?("body_") && item["status"] == "Survived" }
    expect(mutant).not_to be_nil
    File.write(File.join(dir, "config", "saboteur_ignore.rb"), <<~RUBY)
      Saboteur.ignore do |i|
        i.mutation "#{mutant.fetch('id')}", subject: "Loose#value", reason: "accepted for this test"
      end
    RUBY
    replay = saboteur(dir, "--all", "--id", mutant.fetch("id"))
    expect(replay.status).to eq(1), replay.err
    expect(mutants(replay).size).to eq(1)
    expect(mutants(replay).first).to include("id" => mutant.fetch("id"), "status" => "Survived")
    expect(replay.out).not_to include("ignored:")
  end

  it "prints digest, diff and selected test names even for a kill" do
    original = saboteur(dir, "--all", "--subject", "People::Person#adult?")
    mutant = mutants(original).find { |item| item["status"] == "Killed" }
    replay = saboteur(dir, "--all", "--id", mutant.fetch("id"))
    expect(replay.status).not_to eq(2), replay.err
    expect(replay.out).to include(mutant.fetch("id"), "Replay:", "--- a/lib/people.rb", "Selected tests:")
    test_names(original, mutant.fetch("coveredBy")).each { |name| expect(replay.out).to include(name) }
  end
end

RSpec.describe "replay coverage boundaries", :e2e do
  let(:dir) { copy_fixture("people") }

  it "reports an uncovered current mutant as skipped" do
    File.open(File.join(dir, "lib", "people.rb"), "a") do |file|
      file.puts "class Unseen\n  def value\n    123\n  end\nend"
    end
    subject = Saboteur::SubjectFinder.new.call(File.join(dir, "lib", "people.rb")).subjects.find { |item| item.id == "Unseen#value" }
    mutation = Saboteur::MutationSource::Builtin.new.mutations_for(subject).first
    digest = mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
    replay = saboteur(dir, "--all", "--id", digest)
    expect(replay.status).to eq(0)
    expect(mutants(replay).first).to include("id" => digest, "status" => "NoCoverage")
    expect(replay.out).to include(digest, "Selected tests:", "none")
  end

  it "keeps a replay on a one-line uncalled definition uncovered" do
    source = File.join(dir, "lib", "people.rb")
    File.open(source, "a") { |file| file.puts "class LoadReplay; def value; 123; end; end" }
    subject = Saboteur::SubjectFinder.new.call(source).subjects.find { |item| item.id == "LoadReplay#value" }
    mutation = Saboteur::MutationSource::Builtin.new.mutations_for(subject).first
    digest = mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
    replay = saboteur(dir, "--all", "--id", digest)
    expect(replay.status).to eq(0), replay.err
    expect(mutants(replay).first).to include(
      "id" => digest, "status" => "NoCoverage", "statusReason" => "no coverage"
    )
    expect(replay.out).to include(digest, "Selected tests:", "none", "mutant locations not reached: 1")
  end

  it "keeps changed-line scope when resolving --id with --since" do
    source = File.join(dir, "lib", "people.rb")
    File.open(source, "a") { |file| file.puts "class Scoped; def value\n  123\n  456\nend; end" }
    subject = Saboteur::SubjectFinder.new.call(source).subjects.find { |item| item.id == "Scoped#value" }
    mutation = Saboteur::MutationSource::Builtin.new.mutations_for(subject).find do |item|
      !item.coarse && item.edits.all? { |edit| subject.line_of(edit.start_byte) == subject.start_line + 2 }
    end
    expect(mutation).not_to be_nil
    digest = mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
    system("git", "init", "-q", dir, exception: true)
    system("git", "-C", dir, "add", ".", exception: true)
    system("git", "-C", dir, "-c", "user.name=Test", "-c", "user.email=test@example.org",
           "commit", "-qm", "base", exception: true)
    File.write(source, File.read(source).sub("  123\n", "  124\n"))
    replay = saboteur(dir, "--all", "--id", digest, "--since", "HEAD")
    expect(replay.status).to eq(2), replay.err
    expect(replay.err).to include("not found")
  end
end
