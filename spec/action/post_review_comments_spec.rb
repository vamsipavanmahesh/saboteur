# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

# Runs action/post-review-comments against a stand-in GitHub CLI that serves
# canned pages and records every call, so nothing touches GitHub.
RSpec.describe "action/post-review-comments" do
  let(:script) { File.expand_path("../../action/post-review-comments", __dir__) }
  let(:dir) { Dir.mktmpdir("saboteur-review-comments") }
  let(:calls) { File.join(dir, "calls.jsonl") }
  let(:bot) { { "login" => "github-actions[bot]", "type" => "Bot" } }
  let(:person) { { "login" => "mallory", "type" => "User" } }
  let(:marker) { Saboteur::Reporter::ReviewComments }

  after { FileUtils.remove_entry(dir) }

  before do
    gh = File.join(dir, "gh")
    File.write(gh, <<~'RUBY')
      #!/usr/bin/env ruby
      require "json"
      dir = File.dirname(__FILE__)
      File.open(File.join(dir, "calls.jsonl"), "a") { |f| f.puts(JSON.generate(ARGV)) }
      path = ARGV.reject { |a| a.start_with?("-") }.find { |a| a.start_with?("repos/") }.to_s
      key = path.tr("/?&=", "_")
      fail_on = File.join(dir, "fail_#{ARGV[1] == '-X' ? ARGV[2] : 'GET'}")
      if File.exist?(fail_on)
        warn "boom"
        exit 1
      end
      file = File.join(dir, "page_#{key}.json")
      puts(File.exist?(file) ? File.read(file) : "[]")
    RUBY
    FileUtils.chmod(0o755, gh)
  end

  def survivor(digest, line: 5, **extra)
    { "digest" => digest, "path" => "lib/a.rb", "operator" => "comparison", "original" => "a > b",
      "replacement" => "a >= b", "changedLines" => [line] }.merge(extra.transform_keys(&:to_s))
  end

  def write_report(survivors, complete: true)
    path = File.join(dir, "report.json")
    saboteur = { "findings" => { "survivors" => survivors, "survivorsTruncated" => 0 } }
    saboteur["complete"] = complete unless complete == :missing
    File.write(path, JSON.generate({ "saboteur" => saboteur }))
    path
  end

  def serve(path, rows)
    File.write(File.join(dir, "page_#{path.tr('/?&=', '_')}.json"), JSON.generate(rows))
  end

  def run_script(report, **env)
    all = { "SABOTEUR_REPORT_PATH" => report, "SABOTEUR_EVENT_NAME" => "pull_request",
            "SABOTEUR_PR_NUMBER" => "7", "SABOTEUR_HEAD_SHA" => "abc123",
            "SABOTEUR_HEAD_REPO" => "o/r", "GITHUB_REPOSITORY" => "o/r",
            "SABOTEUR_GH" => File.join(dir, "gh") }.merge(env.transform_keys(&:to_s))
    out, status = Open3.capture2e(all, RbConfig.ruby, script)
    [out, status]
  end

  def api_calls
    File.exist?(calls) ? File.readlines(calls).map { |line| JSON.parse(line) } : []
  end

  def writes
    api_calls.select { |args| args.include?("-X") }
  end

  def comments_path
    "repos/o/r/pulls/7/comments?per_page=100&page=1"
  end

  def issue_path
    "repos/o/r/issues/7/comments?per_page=100&page=1"
  end

  it "posts one comment per survivor on its first changed line, pinned to the head commit" do
    out, status = run_script(write_report([survivor("aabbccdd11223344", line: 9)]))

    expect(status).to be_success
    expect(out).to include("1 posted, 0 removed")
    post = writes.first
    expect(post.values_at(1, 2)).to eq(["-X", "POST"])
    expect(post).to include("repos/o/r/pulls/7/comments", "commit_id=abc123", "path=lib/a.rb", "line=9", "side=RIGHT")
    expect(post.find { |arg| arg.start_with?("body=") }).to include("saboteur:digest=aabbccdd11223344")
  end

  it "does not repost a digest the bot already commented, and removes the comment of a fixed survivor" do
    serve(comments_path, [{ "id" => 1, "user" => bot, "body" => "#{marker.marker('aabbccdd11223344')}\nx" },
                          { "id" => 2, "user" => bot, "body" => "#{marker.marker('aabbccdd11223399')}\nx" }])

    out, = run_script(write_report([survivor("aabbccdd11223344")]))

    expect(out).to include("0 posted, 1 removed")
    expect(writes).to eq([["api", "-X", "DELETE", "repos/o/r/pulls/comments/2"]])
  end

  it "hands only bot-authored comments to the planner, so a person's quoted marker is never deleted" do
    serve(comments_path, [{ "id" => 3, "user" => person, "body" => "#{marker.marker('aabbccdd11223399')}\nx" },
                          { "id" => 4, "user" => { "login" => "mallory", "type" => "Bot" },
                            "body" => "#{marker.marker('aabbccdd11223398')}\nx" }])

    run_script(write_report([survivor("aabbccdd11223344")]))

    expect(writes.map { |args| args[2] }).to eq(["POST"])
  end

  it "works with a personal or app token when SABOTEUR_BOT_LOGIN names its account" do
    pat = { "login" => "saboteur-app", "type" => "User" }
    serve(comments_path, [{ "id" => 1, "user" => pat, "body" => "#{marker.marker('aabbccdd11223344')}\nx" },
                          { "id" => 2, "user" => bot, "body" => "#{marker.marker('aabbccdd11223399')}\nx" }])

    out, = run_script(write_report([survivor("aabbccdd11223344"), survivor("aabbccdd11223355")]),
                      SABOTEUR_BOT_LOGIN: "saboteur-app")

    expect(out).to include("1 posted, 0 removed")
    expect(writes.map { |args| args[2] }).to eq(["POST"])
  end

  it "removes nothing unless saboteur.complete is exactly true, but keeps posting" do
    serve(comments_path, [{ "id" => 2, "user" => bot, "body" => "#{marker.marker('aabbccdd11223399')}\nx" }])

    [false, :missing, nil, "true", 1, "false"].each do |value|
      FileUtils.rm_f(calls)
      out, = run_script(write_report([survivor("aabbccdd11223344")], complete: value))
      expect(writes.map { |args| args[2] }).to eq(["POST"]), "complete=#{value.inspect}"
      expect(out).to include("1 posted, 0 removed")
    end
  end

  it "removes comments and the stale summary only for a complete report" do
    serve(issue_path, [{ "id" => 11, "user" => bot, "body" => "#{marker::SUMMARY_MARKER}\nold" }])

    [false, :missing, "true"].each do |value|
      FileUtils.rm_f(calls)
      run_script(write_report([survivor("aabbccdd11223301")], complete: value))
      expect(writes.map { |args| args[2] }).not_to include("DELETE"), "complete=#{value.inspect}"
    end
    run_script(write_report([survivor("aabbccdd11223301")], complete: true))
    expect(writes).to include(["api", "-X", "DELETE", "repos/o/r/issues/comments/11"])
  end

  it "removes nothing from a report that does not say whether it was complete" do
    serve(comments_path, [{ "id" => 2, "user" => bot, "body" => "#{marker.marker('aabbccdd11223399')}\nx" }])
    path = File.join(dir, "bare.json")
    findings = { "survivors" => [], "survivorsTruncated" => 0 }
    File.write(path, JSON.generate({ "saboteur" => { "findings" => findings } }))

    run_script(path)

    expect(writes).to eq([])
  end

  it "skips a comment whose line is not a positive integer" do
    out, = run_script(write_report([survivor("aabbccdd11223344", line: 3)]).then do |path|
      File.write(path, File.read(path).sub('"changedLines":[3]', '"changedLines":["3; rm"]'))
      path
    end)

    expect(writes).to eq([])
    expect(out).not_to include("::warning::")
  end

  it "calls GitHub with an integer line only, however the comment was built" do
    ENV["SABOTEUR_GH"] = File.join(dir, "gh")
    load script
    ["3; rm", 0, -1, 3.0, nil].each do |line|
      expect { post("o/r", 7, "abc", { path: "lib/a.rb", line: line, body: "b" }) }
        .to output(/::warning::saboteur review comments: skipped a comment with no usable line/).to_stdout
    end
    expect(api_calls).to eq([])
    post("o/r", 7, "abc", { path: "lib/a.rb", line: 3, body: "b" })
    expect(writes.size).to eq(1)
  ensure
    ENV.delete("SABOTEUR_GH")
  end

  it "reads every page of existing comments" do
    full = Array.new(100) { |n| { "id" => 100 + n, "user" => bot, "body" => "chat #{n}" } }
    serve(comments_path, full)
    serve("repos/o/r/pulls/7/comments?per_page=100&page=2",
          [{ "id" => 2, "user" => bot, "body" => "#{marker.marker('aabbccdd11223399')}\nx" }])

    run_script(write_report([survivor("aabbccdd11223344")]))

    expect(writes).to include(["api", "-X", "DELETE", "repos/o/r/pulls/comments/2"])
  end

  it "posts nothing for a fork, a non pull_request event or a report without findings" do
    report = write_report([survivor("aabbccdd11223344")])
    run_script(report, SABOTEUR_HEAD_REPO: "fork/r")
    run_script(report, SABOTEUR_EVENT_NAME: "workflow_dispatch")
    run_script(File.join(dir, "bare.json").tap { |path| File.write(path, "{}") })

    expect(api_calls).to eq([])
  end

  it "keeps one updated summary comment when the cap leaves survivors out" do
    serve(issue_path, [{ "id" => 11, "user" => bot, "body" => "#{marker::SUMMARY_MARKER}\nold" }])
    report = write_report([survivor("aabbccdd11223301"), survivor("aabbccdd11223302")])

    out, = run_script(report, SABOTEUR_MAX_COMMENTS: "1", SABOTEUR_RUN_URL: "https://github.com/o/r/actions/runs/5")

    expect(out).to include("1 posted")
    patch = writes.find { |args| args[2] == "PATCH" }
    expect(patch).to include("repos/o/r/issues/comments/11")
    expect(patch.find { |arg| arg.start_with?("body=") }).to include("1 more surviving mutant", "actions/runs/5")
  end

  it "creates the summary when none exists, and deletes a stale one when nothing is left out" do
    run_script(write_report([survivor("aabbccdd11223301"), survivor("aabbccdd11223302")]),
               SABOTEUR_MAX_COMMENTS: "1")
    expect(writes.map { |args| args[2] }).to include("POST")
    expect(writes.last).to include("repos/o/r/issues/7/comments")

    File.delete(calls)
    serve(issue_path, [{ "id" => 11, "user" => bot, "body" => "#{marker::SUMMARY_MARKER}\nold" }])
    run_script(write_report([survivor("aabbccdd11223301")]))
    expect(writes).to include(["api", "-X", "DELETE", "repos/o/r/issues/comments/11"])
  end

  it "ignores a summary marker that a person quoted" do
    serve(issue_path, [{ "id" => 12, "user" => person, "body" => "#{marker::SUMMARY_MARKER}\nold" }])

    run_script(write_report([survivor("aabbccdd11223301")]))

    expect(writes.none? { |args| args.include?("repos/o/r/issues/comments/12") }).to be(true)
  end

  it "warns and still exits 0 when GitHub refuses a post or a delete" do
    serve(comments_path, [{ "id" => 2, "user" => bot, "body" => "#{marker.marker('aabbccdd11223399')}\nx" }])
    FileUtils.touch(File.join(dir, "fail_POST"))
    FileUtils.touch(File.join(dir, "fail_DELETE"))

    out, status = run_script(write_report([survivor("aabbccdd11223344")]))

    expect(status).to be_success
    expect(out.scan("::warning::saboteur review comments:").size).to eq(2)
  end

  it "warns and exits 0 when a listing fails" do
    FileUtils.touch(File.join(dir, "fail_GET"))

    out, status = run_script(write_report([survivor("aabbccdd11223344")]))

    expect(status).to be_success
    expect(out).to include("::warning::saboteur review comments: RuntimeError")
    expect(writes).to eq([])
  end
end
