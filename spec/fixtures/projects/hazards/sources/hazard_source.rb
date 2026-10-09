# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# An external mutation source (the extension point) that proposes one
# hazardous edit per method, by file and byte range.
class HazardSource < Saboteur::MutationSource::Base
  BODIES = {
    # Hangs after starting a grandchild that would outlive a careless runner.
    spin: 'File.write("grandchild.pid", Process.spawn("sleep", "300").to_s); loop {}',
    # Crashes the child while its tests run.
    crash_in_test: 'Process.kill("KILL", Process.pid)',
    # Swaps the private method's result: must stay private and be killed.
    secret: ":leaked"
  }.freeze

  # Appended after the def, so the child fails while re-evaluating.
  TRAILERS = {
    raise_on_load: '; raise "broken mutant"',
    die_on_load: '; Process.kill("KILL", Process.pid)'
  }.freeze

  def name
    "hazards"
  end

  def mutations_for(subject)
    node = subject.node
    edit = if BODIES.key?(node.name)
             body = node.body.location
             edit_for(subject, body.start_offset, body.end_offset, BODIES.fetch(node.name))
           elsif TRAILERS.key?(node.name)
             edit_for(subject, subject.end_byte, subject.end_byte, TRAILERS.fetch(node.name))
           end
    return [] unless edit

    [Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "hazard_#{node.name}",
                                            edits: [edit], source: name)]
  end

  private

  def edit_for(subject, start_byte, end_byte, replacement)
    Saboteur::MutationSource::Edit.new(file: subject.file, start_byte:, end_byte:, replacement:)
  end
end
