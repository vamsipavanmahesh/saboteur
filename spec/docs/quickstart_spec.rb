# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

# Guards against the docs and the config loader drifting apart: the Ruby
# block in the Rails quickstart must load through the real Config.
RSpec.describe "Rails quickstart snippet" do
  root = File.expand_path("../..", __dir__)
  readme = File.read(File.join(root, "README.md"), encoding: "UTF-8")
  rails_section = readme[/^### Rails apps\n(.*?)^###? /m, 1].to_s
  snippet = rails_section[/```ruby\n(.*?)```/m, 1]

  assignments = lambda do |text|
    text.to_s.gsub(/<[^>]+>/, "").scan(/^\s*(c\.\w+ = [^#\n]+)/).flatten.map { |line| line.strip.gsub(/\s+/, " ") }
  end

  it "exists in the README" do
    expect(snippet).not_to be_nil
  end

  it "loads through Saboteur::Config and enables Rails" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "saboteur.rb"), snippet)
      config = Saboteur::Config.load(root: dir)
      expect([config["rails"], config["include"], config["require"]])
        .to eq([true, ["app/**/*.rb"], ["./config/environment"]])
    end
  end

  it "matches the landing page Rails block" do
    html = File.read(File.join(root, "docs/index.html"), encoding: "UTF-8")
    block = html[%r{<h3>Rails apps</h3>.*?<pre><code>(.*?)</code></pre>}m, 1]
    expect(assignments.call(block)).to eq(assignments.call(snippet))
  end

  it "keeps the documented plain-gem defaults the quickstart warns about" do
    defaults = Saboteur::Config::DEFAULTS
    expect(defaults.values_at("include", "rails", "jobs")).to eq([["lib/**/*.rb"], false, 1])
  end
end
