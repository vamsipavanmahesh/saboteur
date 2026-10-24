require 'rails_helper'
RSpec.describe 'Story HTML metadata contract', type: :request do
  it 'includes the canonical image and local author metadata' do
    story = create(:story)
    get Routes.title_path(story)
    expect(response).to have_http_status(200)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('meta[property="og:image"]')&.[]('content')).to eq(Routes.story_image_or_logo_url(story))
    expect(html.css('meta[property="article:author"]').map { |tag| tag['content'] }).to include(Routes.user_url(story.user))
  end
end
