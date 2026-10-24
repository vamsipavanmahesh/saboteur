# typed: false
# INDEPENDENT VERIFICATION SPECIMEN - temporary file, not an app suite edit.
# Field-run survivor triage, PR #2204, app/models/story.rb:777
#   is_deleted? || (user.is_banned? && score < 0 && is_moderated == false)
# Targets: 56ec2857eb8103bd (<  -> <=), 695982748e0e8ebb (0 -> 1), 9786b8df27eddc21 (0 -> -1)
require "rails_helper"

describe Story do
  describe "#is_gone? score boundary (independent verification specimen)" do
    it "returns false when a banned user's story has score exactly 0" do
      user = build_stubbed(:user, :banned)
      story = build_stubbed(:story, score: 0, is_deleted: false, is_moderated: false, user: user)

      expect(story.is_gone?).to be false
    end

    it "returns true when a banned user's story has score -1" do
      user = build_stubbed(:user, :banned)
      story = build_stubbed(:story, score: -1, is_deleted: false, is_moderated: false, user: user)

      expect(story.is_gone?).to be true
    end
  end
end
