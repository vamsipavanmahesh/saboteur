# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module Saboteur
  # One wording for the two survivor follow-ups a user copies: replaying
  # one mutant and accepting one in the ignore file. The run screen (Next
  # steps) and `saboteur survivors --show` share these strings so the two
  # surfaces never drift (#1167).
  module SurvivorGuidance
    REPLAY_CAVEAT = "(add this run's own --config, --since, --subject, --test and source options)"
    IGNORE_INTRO = "accept an equivalent one: add to your ignore file"
    IGNORE_CONFIG = "(c.ignore_file, default #{Config::IGNORE_FILE}):".freeze
    REASON_PLACEHOLDER = "why it is equivalent"

    module_function

    def replay_command(digest, seed: nil)
      "saboteur run --id #{digest}#{" --seed #{seed}" if seed}"
    end

    # One line, paste-ready. todo names what the user must still fill in
    # (a capped report omits the subject for some digests).
    def ignore_entry(digest, subject_id, todo: nil)
      entry = %(i.mutation "#{digest}", subject: "#{subject_id}", reason: "#{REASON_PLACEHOLDER}")
      todo ? "#{entry} # TODO: #{todo}" : entry
    end

    # The entry wrapped so it pastes into the ignore file as-is (#1194).
    def ignore_block(digest, subject_id, todo: nil)
      "Saboteur.ignore do |i|\n  #{ignore_entry(digest, subject_id, todo: todo)}\nend"
    end
  end
end
