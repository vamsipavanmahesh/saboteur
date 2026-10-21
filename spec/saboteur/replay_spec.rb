# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/replay"

require "stringio"

RSpec.describe Saboteur::Replay do
  let(:subject) { person_subject }
  let(:mutation) { comparison_mutation }
  let(:text) { subject.apply(mutation.edits) }
  let(:digest) { mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source) }

  it "selects exactly the full digest, including fine mutants" do
    candidates = instance_double(Saboteur::Engine::Candidates)
    allow(candidates).to receive(:for).with(subject).and_return([[mutation, text]])
    replay = described_class.new(digest: digest)
    expect(replay.select([subject], candidates)).to eq([subject, [mutation, text]])
  end

  it "refuses an unknown digest before running tests" do
    candidates = instance_double(Saboteur::Engine::Candidates, for: [])
    replay = described_class.new(digest: "0" * 16)
    expect { replay.select([subject], candidates) }.to raise_error(Saboteur::ConfigError, /not found/)
  end

  it "refuses ambiguous digests rather than choosing one" do
    candidates = instance_double(Saboteur::Engine::Candidates, for: [[mutation, text], [mutation, text]])
    replay = described_class.new(digest: digest)
    expect { replay.select([subject], candidates) }.to raise_error(Saboteur::ConfigError, /ambiguous/)
  end

  it "names the digest in the not found and ambiguous messages" do
    candidates = instance_double(Saboteur::Engine::Candidates, for: [])
    unknown = "a" * 16
    expect { described_class.new(digest: unknown).select([subject], candidates) }
      .to raise_error(Saboteur::ConfigError, "mutant #{unknown} not found in the selected current source")
    twice = instance_double(Saboteur::Engine::Candidates, for: [[mutation, text], [mutation, text]])
    expect { described_class.new(digest: digest).select([subject], twice) }
      .to raise_error(Saboteur::ConfigError,
                      "mutant #{digest} is ambiguous; narrow --subject or include files")
  end

  it "does not accept a digest with anything before or after the 16 hex digits" do
    ["zz#{digest}", "#{digest}zz", "#{digest}\n", "\n#{digest}"].each do |bad|
      expect { described_class.new(digest: bad) }.to raise_error(Saboteur::ConfigError, /16 lowercase hexadecimal/)
    end
  end

  it "does not accept digest prefixes" do
    expect { described_class.new(digest: digest[0, 8]) }
      .to raise_error(Saboteur::ConfigError, /16 lowercase hexadecimal/)
  end
end

RSpec.describe Saboteur::Replay, "diff scope" do
  it "does not resolve a fine digest outside the changed lines" do
    subject = person_subject
    mutation = comparison_mutation
    digest = mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
    candidates = instance_double(Saboteur::Engine::Candidates, for: [[mutation, subject.apply(mutation.edits)]])
    scope = Saboteur::Engine::DiffScope.new(subject.file => Set[999])
    expect { described_class.new(digest: digest).select([subject], candidates, scope: scope) }
      .to raise_error(Saboteur::ConfigError, /not found/)
  end
end

RSpec.describe Saboteur::Replay, "nonmatching candidates" do
  it "skips existing candidates with a different digest" do
    subject = person_subject
    mutation = comparison_mutation
    candidates = instance_double(Saboteur::Engine::Candidates, for: [[mutation, subject.apply(mutation.edits)]])
    expect { described_class.new(digest: "0" * 16).select([subject], candidates) }
      .to raise_error(Saboteur::ConfigError, /not found/)
  end
end

RSpec.describe Saboteur::Replay, "and the hazard guard (issue #102)" do
  # The replay path selects from the guarded candidate list, so a digest
  # naming a suppressed mutant is refused; --allow-hazardous drops the
  # guard and replays it.
  def hazard_subject
    subject_named("class K\n  def m\n    FileUtils.rm_rf(File.join(Dir.pwd, \"build\"))\n  end\nend\n", "K#m")
  end

  def candidates_with(guard)
    source = Class.new(Saboteur::MutationSource::Base) do
      define_method(:mutations_for) do |subject|
        at = subject.file_source.index('"build"')
        edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + 7,
                                                  replacement: '"."')
        [Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "literal_string", edits: [edit])]
      end
    end.new
    Saboteur::Engine::Candidates.new([source], Saboteur::Engine::Diagnostics.new(StringIO.new),
                                     hazard_guard: guard)
  end

  def hazard_digest(subject)
    mutation, = candidates_with(nil).for(subject).first
    mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
  end

  it "refuses a digest that names a suppressed mutant" do
    subject = hazard_subject
    expect { described_class.new(digest: hazard_digest(subject)).select([subject], candidates_with(Saboteur::MutationSource::HazardGuard.new)) }
      .to raise_error(Saboteur::ConfigError, /not found/)
  end

  it "replays the same digest once the guard is off (--allow-hazardous)" do
    subject = hazard_subject
    mutation, text = candidates_with(nil).for(subject).first
    expect(described_class.new(digest: hazard_digest(subject)).select([subject], candidates_with(nil)))
      .to eq([subject, [mutation, text]])
  end
end
