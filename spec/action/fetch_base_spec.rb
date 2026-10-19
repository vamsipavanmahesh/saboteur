# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "base64"
require "fileutils"
require "open3"
require "socket"
require "tmpdir"

# Runs action/fetch-base against a local HTTP server that records what git
# sends, so the header's presence, shape and scope are checked on the wire.
RSpec.describe "action/fetch-base" do
  let(:script) { File.expand_path("../../action/fetch-base", __dir__) }
  let(:workspace) { Dir.mktmpdir("saboteur-fetch-base") }
  let(:server) { TCPServer.new("127.0.0.1", 0) }
  let(:url) { "http://127.0.0.1:#{server.addr[1]}" }
  let(:requests) { [] }
  let(:base) { "b" * 40 }
  let(:token) { "ghs_secrettoken123" }

  before do
    Thread.new do
      loop do
        client = server.accept
        lines = []
        while (line = client.gets) && line != "\r\n"
          lines << line.chomp
        end
        requests << lines
        client.write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        client.close
      end
    rescue IOError, Errno::EBADF
      nil
    end
    git("init", "-q", "-b", "main")
    git("remote", "add", "origin", "#{url}/o/r.git")
  end

  after do
    server.close
    FileUtils.remove_entry(workspace)
  end

  def git(*args)
    out, status = Open3.capture2e("git", *args, chdir: workspace)
    raise out unless status.success?

    out
  end

  def run_fetch(dir: workspace, **environment)
    all = { "SABOTEUR_EVENT_NAME" => "workflow_dispatch", "SABOTEUR_BASE_SHA" => base,
            "GITHUB_SERVER_URL" => url, "SABOTEUR_FETCH_TOKEN" => token,
            "GIT_TERMINAL_PROMPT" => "0" }.merge(environment)
    Open3.capture2e(all, "bash", script, chdir: dir)
  end

  def authorizations
    requests.flat_map { |lines| lines.grep(/\Aauthorization:/i) }
  end

  it "sends the token as a basic auth header and leaves nothing in the git config" do
    _, status = run_fetch

    expect(status.exitstatus).to eq(0)
    expect(authorizations).not_to be_empty
    expect(authorizations.uniq).to eq(["AUTHORIZATION: basic #{Base64.strict_encode64("x-access-token:#{token}")}"])
    expect(File.read(File.join(workspace, ".git",
                               "config"))).not_to include(token, Base64.strict_encode64("x-access-token:#{token}"))
  end

  it "replaces a header an earlier checkout persisted, so there is one Authorization header" do
    git("config", "http.#{url}/.extraheader", "AUTHORIZATION: basic #{Base64.strict_encode64('x-access-token:old')}")

    run_fetch

    expect(requests.first.grep(/\Aauthorization:/i).size).to eq(1)
    expect(authorizations.first).to include(Base64.strict_encode64("x-access-token:#{token}"))
  end

  it "sends no Authorization header without a token" do
    run_fetch("SABOTEUR_FETCH_TOKEN" => "")

    expect(requests).not_to be_empty
    expect(authorizations).to eq([])
  end

  it "never prints the token" do
    output, = run_fetch

    expect(output).not_to include(token, Base64.strict_encode64("x-access-token:#{token}"))
  end

  it "exits 0 when GitHub refuses the fetch" do
    _, status = run_fetch("SABOTEUR_EVENT_NAME" => "pull_request", "GITHUB_REF" => "refs/pull/7/merge")

    expect(status.exitstatus).to eq(0)
  end

  it "makes no request for a base SHA that is not 40 hex digits, or a ref that is not a merge ref" do
    run_fetch("SABOTEUR_BASE_SHA" => "main")
    run_fetch("SABOTEUR_EVENT_NAME" => "pull_request", "GITHUB_REF" => "refs/heads/feature")

    expect(requests).to eq([])
  end

  it "does not fetch a base commit the checkout already has" do
    File.write(File.join(workspace, "f"), "x")
    git("add", ".")
    git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "x")

    run_fetch("SABOTEUR_BASE_SHA" => git("rev-parse", "HEAD").strip)

    expect(requests).to eq([])
  end

  it "sends the header only to the configured server" do
    other = "http://localhost:#{server.addr[1]}"
    git("remote", "set-url", "origin", "#{other}/o/r.git")

    run_fetch

    expect(requests).not_to be_empty
    expect(authorizations).to eq([])
  end

  it "authenticates the deepening fetches of a shallow pull request checkout too" do
    source = File.join(workspace, "source")
    shallow = File.join(workspace, "shallow")
    FileUtils.mkdir_p(source)
    identity = ["-c", "user.name=t", "-c", "user.email=t@example.com"]
    git("-C", source, "init", "-q")
    2.times { git("-C", source, *identity, "commit", "-q", "--allow-empty", "-m", "x") }
    git("clone", "-q", "--depth", "1", "file://#{source}", shallow)
    git("-C", shallow, "remote", "set-url", "origin", "#{url}/o/r.git")
    tree = git("-C", shallow, "rev-parse", "HEAD^{tree}").strip
    unrelated = git("-C", shallow, *identity, "commit-tree", "-m", "orphan", tree).strip

    run_fetch(dir: shallow, "SABOTEUR_EVENT_NAME" => "pull_request", "SABOTEUR_BASE_SHA" => unrelated,
              "GITHUB_REF" => "refs/pull/7/merge")

    expect(requests.size).to be >= 1
    expect(authorizations.uniq.size).to eq(1)
  end
end
