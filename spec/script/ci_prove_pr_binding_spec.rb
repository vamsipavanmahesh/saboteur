# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Drives script/ci-prove-pr-binding with a stubbed curl, so the GraphQL
# binding checks are tested without the GitHub API.
RSpec.describe "script/ci-prove-pr-binding" do
  let(:script) { File.expand_path("../../script/ci-prove-pr-binding", __dir__) }
  let(:workspace) { Dir.mktmpdir("ci-prove-pr-binding") }
  let(:head_sha) { "a" * 40 }
  let(:base_sha) { "b" * 40 }

  after { FileUtils.remove_entry(workspace) }

  # Stubs curl on PATH. Without a response the stub fails the way curl -f
  # does on an HTTP error (exit 22), so the script's fail-closed path runs.
  def write_curl_stub(response: nil, exit_status: 0)
    bin = File.join(workspace, "bin")
    FileUtils.mkdir_p(bin)
    fixture = File.join(workspace, "response.json")
    File.write(fixture, response) if response
    File.write(File.join(bin, "curl"), <<~SH)
      #!/usr/bin/env bash
      printf '%s\n' "$@" >> "#{File.join(workspace, 'curl-args.log')}"
      [ -f "#{fixture}" ] || exit 22
      cat "#{fixture}"
      exit #{exit_status}
    SH
    File.chmod(0o755, File.join(bin, "curl"))
  end

  def graphql_response(head_repo: "owner/repo", head_oid: head_sha, base_oid: base_sha)
    JSON.generate(data: { repository: { pullRequest: {
                    headRepository: { nameWithOwner: head_repo }, headRefOid: head_oid, baseRefOid: base_oid
                  } } })
  end

  def prove(env = {})
    write_curl_stub unless File.exist?(File.join(workspace, "bin", "curl"))
    defaults = {
      "GH_TOKEN" => "token",
      "GITHUB_REPOSITORY" => "owner/repo",
      "GITHUB_SHA" => head_sha,
      "PR_NUMBER" => "7",
      "BASE_SHA" => base_sha,
      "REQUIRE_OWN_REPO" => "0",
      "PATH" => "#{File.join(workspace, 'bin')}:#{ENV.fetch('PATH')}"
    }
    Open3.capture2e(defaults.merge(env), script)
  end

  it "passes when the dispatch is the pull request's exact head and base" do
    write_curl_stub(response: graphql_response)
    output, status = prove
    expect([status.exitstatus, output]).to eq([0, ""])
  end

  it "asks the API for the head, the base and the head repository" do
    write_curl_stub(response: graphql_response)
    _, status = prove
    args = File.read(File.join(workspace, "curl-args.log"))
    expect(status.exitstatus).to eq(0)
    expect(args).to include("baseRefOid").and include("headRefOid").and include("nameWithOwner")
  end

  it "sends a GraphQL payload that parses as valid JSON" do
    write_curl_stub(response: graphql_response)
    _output, status = prove
    line = File.readlines(File.join(workspace, "curl-args.log"),
                          chomp: true).find { |arg| arg.start_with?('{"query"') }
    parsed = JSON.parse(line)
    query = parsed["query"]
    expect([status.exitstatus, query]).to match([
                                                  0,
                                                  a_string_including('repository(owner:"owner",name:"repo")')
                                                    .and(include("pullRequest(number:7)"))
                                                    .and(include("headRefOid")).and(include("baseRefOid"))
                                                    .and(include("nameWithOwner"))
                                                ])
  end

  it "fails closed when the dispatched SHA is not the pull request's head" do
    write_curl_stub(response: graphql_response(head_oid: "c" * 40))
    output, status = prove
    expect([status.exitstatus, output]).to match([1, /not the current head of PR #7/])
  end

  it "fails closed when the base_sha input is not the pull request's base" do
    write_curl_stub(response: graphql_response(base_oid: "d" * 40))
    output, status = prove
    expect([status.exitstatus, output]).to match([1, /not the base of PR #7/])
  end

  it "allows a fork pull request when the own-repo guard is off" do
    write_curl_stub(response: graphql_response(head_repo: "contributor/fork"))
    _, status = prove("REQUIRE_OWN_REPO" => "0")
    expect(status.exitstatus).to eq(0)
  end

  it "refuses a fork pull request when the own-repo guard is on" do
    write_curl_stub(response: graphql_response(head_repo: "contributor/fork"))
    output, status = prove("REQUIRE_OWN_REPO" => "1")
    expect([status.exitstatus, output]).to match([1, /fork or unknown head repo/])
  end

  it "rejects a non-numeric pull request number before calling the API" do
    write_curl_stub(response: graphql_response)
    output, status = prove("PR_NUMBER" => "7){repository")
    expect([status.exitstatus, output]).to match([1, /must be digits/])
    expect(File.exist?(File.join(workspace, "curl-args.log"))).to be(false)
  end

  it "rejects a base SHA that is not 40 hex characters" do
    write_curl_stub(response: graphql_response)
    output, status = prove("BASE_SHA" => "abc123")
    expect([status.exitstatus, output]).to match([1, /40-character base commit/])
  end

  it "fails closed when the API call itself fails" do
    write_curl_stub
    output, status = prove
    expect([status.exitstatus, output]).to match([1, /refusing to run unbound/])
  end
end
