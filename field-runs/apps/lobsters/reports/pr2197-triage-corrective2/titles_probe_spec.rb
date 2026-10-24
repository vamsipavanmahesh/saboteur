# TEMPORARY VERIFICATION SPECIMEN (task-agent proof probe, not an app change; removed after proofs)
# v2: R2/D2 count h1 tags - views have their own h1; @title_h1=false suppresses the duplicate layout h1
require "rails_helper"

describe "page titles (verification probe)", type: :request do
  it "PROBE-I1 inbox/all renders the Inbox title" do
    sign_in create(:user)
    get "/inbox/all"
    expect(response.body).to include("<title>Inbox | Lobsters</title>")
  end

  it "PROBE-M1 mod_mails renders the ModMail title" do
    sign_in create(:user)
    get "/mod_mails"
    expect(response.body).to include("<title>ModMail | Lobsters</title>")
  end

  it "PROBE-SE1 settings renders the Settings title" do
    sign_in create(:user)
    get "/settings"
    expect(response.body).to include("<title>Settings | Lobsters</title>")
  end

  it "PROBE-R1 reparents/new renders the Reparent title" do
    sign_in create(:user, :admin)
    target = create(:user)
    get "/mod/reparents/new", params: {id: target.username}
    expect(response.body).to include("<title>Reparent #{target.username} | Lobsters</title>")
  end

  it "PROBE-R2 reparents/new suppresses the title h1" do
    sign_in create(:user, :admin)
    target = create(:user)
    get "/mod/reparents/new", params: {id: target.username}
    expect(response.body.scan(/<h1/).size).to eq 1 # layout h1 suppressed; view h1 only
  end

  it "PROBE-D1 domains/edit renders the Edit Domain title" do
    sign_in create(:user, :moderator)
    get "/mod/domains/example.com/edit"
    expect(response.body).to include("<title>Edit Domain example.com | Lobsters</title>")
  end

  it "PROBE-D2 domains/edit suppresses the title h1" do
    sign_in create(:user, :moderator)
    get "/mod/domains/example.com/edit"
    expect(response.body.scan(/<h1/).size).to eq 1 # layout h1 suppressed; view h1 only
  end

  it "PROBE-S1 search with what renders the Search results title" do
    sign_in create(:user)
    create(:story, title: "probequeryxyz title")
    get "/search", params: {q: "probequeryxyz", what: "stories"}
    expect(response.body).to include("<title>Search results | Lobsters</title>")
  end

  it "PROBE-S2 search without what does not render the Search results title" do
    sign_in create(:user)
    create(:story, title: "probequeryxyz title")
    get "/search", params: {q: "probequeryxyz"}
    expect(response.body).not_to include("Search results |")
  end
end
