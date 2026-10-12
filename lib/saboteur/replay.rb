# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # Resolves one exact digest from current source, before caps, ignore suppression or incremental reuse.
  class Replay
    def initialize(digest:)
      unless digest.match?(/\A[0-9a-f]{16}\z/)
        raise ConfigError, "--id needs a full 16 lowercase hexadecimal mutant digest"
      end

      @digest = digest
    end

    def select(subjects, candidates, scope: nil)
      match = nil
      subjects.each do |subject|
        list = candidates.for(subject)
        list = scope.restrict(subject, list) if scope
        list.each do |mutation, text|
          digest = mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
          next unless digest == @digest
          raise ConfigError, "mutant #{@digest} is ambiguous; narrow --subject or include files" if match

          match = [subject, [mutation, text]]
        end
      end
      raise ConfigError, "mutant #{@digest} not found in the selected current source" unless match

      match
    end
  end
end
