# TEMPORARY VERIFICATION SPECIMEN (task-agent proof probe, not an app change; removed after proofs)
require "rails_helper"

describe "FlaggedCommenters having-threshold (verification probe)", type: :request do
  before { sign_in create(:user, :moderator) }

  it "PROBE-F1 below-threshold flagged commenter is not listed" do
    user = create(:user)
    2.times { c = create(:comment, user: user); c.update_column(:flags, 3) }
    get "/~#{user.username}"
    expect(response.body).not_to include("/mod/commenters/1m#")
  end

  it "PROBE-F2 above-threshold flagged commenter is listed (fixture sanity)" do
    user = create(:user)
    6.times { c = create(:comment, user: user); c.update_column(:flags, 2) }
    get "/~#{user.username}"
    expect(response.body).to include("/mod/commenters/1m##{user.username}")
  end
end
