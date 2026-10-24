# TEMPORARY VERIFICATION SPECIMEN (task-agent proof probe, not an app change; removed after proofs)
require "rails_helper"

describe Story do
  describe "hide/save predicates (verification probe)" do
    let(:user) { create(:user) }
    let(:other) { create(:user) }
    let(:story) { create(:story) }
    let(:other_story) { create(:story) }

    it "PROBE-H1 hidden story is hidden for that user" do
      HiddenStory.create!(user: user, story: story)
      expect(story.is_hidden_by_user?(user)).to eq true
    end
    it "PROBE-H2 unhidden story is not hidden" do
      expect(story.is_hidden_by_user?(user)).to eq false
    end
    it "PROBE-H3 hidden by another user is not hidden for user" do
      HiddenStory.create!(user: other, story: story)
      expect(story.is_hidden_by_user?(user)).to eq false
    end
    it "PROBE-H4 another story hidden by user does not hide this story" do
      HiddenStory.create!(user: user, story: other_story)
      expect(story.is_hidden_by_user?(user)).to eq false
    end
    it "PROBE-S1 saved story is saved for that user" do
      SavedStory.create!(user: user, story: story)
      expect(story.is_saved_by_user?(user)).to eq true
    end
    it "PROBE-S2 unsaved story is not saved" do
      expect(story.is_saved_by_user?(user)).to eq false
    end
    it "PROBE-S3 saved by another user is not saved for user" do
      SavedStory.create!(user: other, story: story)
      expect(story.is_saved_by_user?(user)).to eq false
    end
    it "PROBE-S4 another story saved by user does not save this story" do
      SavedStory.create!(user: user, story: other_story)
      expect(story.is_saved_by_user?(user)).to eq false
    end
  end
end
