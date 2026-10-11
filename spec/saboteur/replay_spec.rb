# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "saboteur/replay"

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
