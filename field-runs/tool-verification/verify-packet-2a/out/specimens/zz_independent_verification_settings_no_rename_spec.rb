# typed: false
# INDEPENDENT VERIFICATION SPECIMEN - temporary file, not an app suite edit.
# Field-run survivor triage, PR #2156, app/controllers/settings_controller.rb:51
#   if @edit_user.username_previously_changed?
# Target: 84a2b3ca16355339 (condition -> true). Under the mutant, an update that
# does NOT change the username still calls Username.rename!, creating a Moderation.
require "rails_helper"

describe SettingsController do
  describe "update without a username change (independent verification specimen)" do
    let(:user) { create(:user) }

    it "records no moderation log when the username is unchanged" do
      stub_login_as user

      expect {
        post :update, params: {user: {password: "", username: user.username}}
      }.not_to change(Moderation, :count)
      expect(response.status).to eq(200)
      expect(user.reload.username).to eq(user.username)
    end
  end
end
