# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # Resolves one exact digest from current source, before caps or coarse gating.
  class Replay
    def initialize(digest:)
      unless digest.match?(/\A[0-9a-f]{16}\z/)
        raise ConfigError, "--id needs a full 16 lowercase hexadecimal mutant digest"
      end

      @digest = digest
    end

    def select(subjects, candidates)
      matches = subjects.flat_map do |subject|
        candidates.for(subject).filter_map do |mutation, text|
          digest = mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
          [subject, [mutation, text]] if digest == @digest
        end
      end
      raise ConfigError, "mutant #{@digest} not found in the selected current source" if matches.empty?
      raise ConfigError, "mutant #{@digest} is ambiguous; narrow --subject or include files" if matches.size > 1

      matches.first
    end
  end
end
