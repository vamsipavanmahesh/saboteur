# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "yaml"

# Guards against the docs and the config loader drifting apart: every YAML
# block in the Rails quickstart must load through the real Config.
RSpec.describe "Rails quickstart snippet" do
  root = File.expand_path("../..", __dir__)
  readme = File.read(File.join(root, "README.md"))
  rails_section = readme[/^### Rails apps\n(.*?)^###? /m, 1].to_s
  snippet = rails_section[/```yaml\n(.*?)```/m, 1]

  it "exists in the README" do
    expect(snippet).not_to be_nil
  end

  it "loads through Saboteur::Config and enables Rails" do
    config = Saboteur::Config.new(YAML.safe_load(snippet), root: Dir.pwd)
    expect([config["rails"], config["include"], config["require"]])
      .to eq([true, ["app/**/*.rb"], ["./config/environment"]])
  end

  it "matches the landing page Rails block" do
    html = File.read(File.join(root, "docs/index.html"))
    block = html[%r{<h3>Rails apps</h3>.*?<pre><code>(.*?)</code></pre>}m, 1].to_s
    page = YAML.safe_load(block.gsub(/<[^>]+>/, ""))
    expect(page).to eq(YAML.safe_load(snippet).merge("jobs" => 4))
  end

  it "keeps the documented plain-gem defaults the quickstart warns about" do
    defaults = Saboteur::Config::DEFAULTS
    expect(defaults.values_at("include", "rails", "jobs")).to eq([["lib/**/*.rb"], false, 1])
  end
end
