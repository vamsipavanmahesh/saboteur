# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

module SubjectHelpers
  # Writes source to a temp file and returns the subjects found in it.
  def subjects_in(source, name: "subject_fixture.rb")
    dir = Dir.mktmpdir("saboteur-spec-")
    @subject_dirs = (@subject_dirs || []) << dir
    path = File.join(File.realpath(dir), name)
    File.write(path, source)
    Saboteur::SubjectFinder.new.call(path).subjects
  end

  def subject_named(source, id)
    subjects_in(source).find { |subject| subject.id == id } or raise "no subject #{id}"
  end

  def mutated_texts(subject, source: Saboteur::MutationSource::Builtin.new)
    source.mutations_for(subject).map { |mutation| [mutation.operator, subject.apply(mutation.edits)] }
  end
end

RSpec.configure do |config|
  config.include SubjectHelpers
  config.after do
    (@subject_dirs || []).each { |dir| FileUtils.rm_rf(dir) }
  end
end
