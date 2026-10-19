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

  let(:repo_dir) { File.join(dir, "checkout") }
  let(:git_env) do
    { "GIT_AUTHOR_NAME" => "t", "GIT_AUTHOR_EMAIL" => "t@example.com",
      "GIT_COMMITTER_NAME" => "t", "GIT_COMMITTER_EMAIL" => "t@example.com" }
  end

  def git(*args)
    out, status = Open3.capture2e(git_env, "git", *args, chdir: repo_dir)
    raise out unless status.success?

    out.strip
  end

  def commit_file(path, text)
    FileUtils.mkdir_p(File.dirname(File.join(repo_dir, path)))
    File.write(File.join(repo_dir, path), text)
    git("add", ".")
    git("commit", "-q", "-m", "change")
    git("rev-parse", "HEAD")
  end

  def numbered(count)
    (1..count).map { |n| "line #{n}\n" }.join
  end

  # A pull request head and a moved base, merged the way GitHub's merge ref is.
  # Leaves the checkout on the merge commit and returns the head commit.
  def merge_checkout(head_text:, base_text:, evil: nil)
    FileUtils.mkdir_p(repo_dir)
    git("init", "-q", "-b", "main")
    root = commit_file("lib/a.rb", numbered(10))
    git("checkout", "-q", "-b", "pr")
    head = commit_file("lib/a.rb", head_text)
    git("checkout", "-q", "-b", "merge", root)
    commit_file("lib/a.rb", base_text)
    git("merge", "-q", "--no-edit", "--no-commit", "pr")
    path = File.join(repo_dir, "lib/a.rb")
    File.write(path, evil.call(File.read(path))) if evil
    git("add", ".")
    git("commit", "-q", "-m", "merge")
    head
  end

  def posted_lines
    writes.map { |args| args.find { |arg| arg.start_with?("line=") } }
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
            "SABOTEUR_PR_NUMBER" => "7",
            "SABOTEUR_HEAD_REPO" => "o/r", "GITHUB_REPOSITORY" => "o/r",
            "SABOTEUR_GH" => File.join(dir, "gh") }.merge(env.transform_keys(&:to_s))
    all["SABOTEUR_HEAD_SHA"] = checkout_head unless env.key?(:SABOTEUR_HEAD_SHA) || env.key?("SABOTEUR_HEAD_SHA")
    out, status = Open3.capture2e(all, RbConfig.ruby, script, chdir: File.directory?(repo_dir) ? repo_dir : dir)
    [out, status]
  end

  def checkout_head
    return git("rev-parse", "HEAD") if File.directory?(File.join(repo_dir, ".git"))

    FileUtils.mkdir_p(repo_dir)
    git("init", "-q", "-b", "main")
    commit_file("lib/a.rb", numbered(20))
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
    expect(post).to include("repos/o/r/pulls/7/comments", "commit_id=#{checkout_head}", "path=lib/a.rb", "line=9",
                            "side=RIGHT")
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

  it "compares the bot login without regard to case" do
    mixed = { "login" => "Saboteur-App", "type" => "User" }
    serve(comments_path, [{ "id" => 1, "user" => mixed, "body" => "#{marker.marker('aabbccdd11223344')}\nx" },
                          { "id" => 2, "user" => mixed, "body" => "#{marker.marker('aabbccdd11223399')}\nx" }])

    out, = run_script(write_report([survivor("aabbccdd11223344")]), SABOTEUR_BOT_LOGIN: "saboteur-app")

    expect(out).to include("0 posted, 1 removed")
    expect(writes).to eq([["api", "-X", "DELETE", "repos/o/r/pulls/comments/2"]])
  end

  it "falls back to github-actions[bot] when SABOTEUR_BOT_LOGIN is empty or blank" do
    serve(comments_path, [{ "id" => 2, "user" => bot, "body" => "#{marker.marker('aabbccdd11223399')}\nx" },
                          { "id" => 3, "user" => { "login" => "", "type" => "Bot" },
                            "body" => "#{marker.marker('aabbccdd11223398')}\nx" }])

    ["", "  "].each do |value|
      FileUtils.rm_f(calls)
      run_script(write_report([survivor("aabbccdd11223344")]), SABOTEUR_BOT_LOGIN: value)
      expect(writes.map { |args| args[3] }).to include("repos/o/r/pulls/comments/2"), "login=#{value.inspect}"
      expect(writes.map { |args| args[3] }).not_to include("repos/o/r/pulls/comments/3")
    end
  end

  it "trims whitespace around the bot login, and ignores comments with no login" do
    serve(comments_path, [{ "id" => 1, "user" => nil, "body" => "#{marker.marker('aabbccdd11223344')}\nx" },
                          { "id" => 2, "user" => bot, "body" => "#{marker.marker('aabbccdd11223399')}\nx" }])

    run_script(write_report([survivor("aabbccdd11223344")]), SABOTEUR_BOT_LOGIN: " github-actions[bot] ")

    expect(writes.map { |args| args[2] }).to eq(%w[DELETE POST])
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

  describe "line numbers on a merge checkout" do
    def edit(text, number, to)
      text.sub("line #{number}\n", to)
    end

    def run_merged(head_text, base_text, line, evil: nil)
      head = merge_checkout(head_text: head_text, base_text: base_text, evil: evil)
      run_script(write_report([survivor("aabbccdd11223344", line: line)]), SABOTEUR_HEAD_SHA: head)
    end

    it "moves a line back to the head commit when the base added lines above it" do
      out, = run_merged(edit(numbered(10), 7, "changed 7\n"), "base 1\nbase 2\n#{numbered(10)}", 9)

      expect(out).to include("1 posted")
      expect(posted_lines).to eq(["line=7"])
    end

    it "moves a line back when the base removed lines above it" do
      out, = run_merged(edit(numbered(10), 9, "changed 9\n"), numbered(10).sub("line 2\nline 3\n", ""), 7)

      expect(out).to include("1 posted")
      expect(posted_lines).to eq(["line=9"])
    end

    it "moves the line right after an insertion, and not the line right before a deletion" do
      head_text = edit(numbered(10), 9, "changed 9\n")
      run_merged(head_text, "base 1\nbase 2\n#{numbered(10)}", 3)
      expect(posted_lines).to eq(["line=1"])

      FileUtils.remove_entry(repo_dir)
      FileUtils.rm_f(calls)
      run_merged(head_text, numbered(10).sub("line 4\nline 5\n", ""), 3)
      expect(posted_lines).to eq(["line=3"])
    end

    it "does not shift a line for a base change of a single line above it" do
      out, = run_merged(edit(numbered(10), 9, "changed 9\n"), edit(numbered(10), 2, "base 2\n"), 5)

      expect(out).to include("1 posted")
      expect(posted_lines).to eq(["line=5"])
    end

    it "posts nothing when the checkout merges more than the head commit" do
      head = merge_checkout(head_text: edit(numbered(10), 9, "changed 9\n"),
                            base_text: edit(numbered(10), 2, "base 2\n"))
      git("checkout", "-q", "-b", "other", "main")
      other = commit_file("lib/other.rb", "x\n")
      git("checkout", "-q", "main")
      commit_file("lib/main.rb", "y\n")
      git("merge", "-q", "--no-edit", "pr", other)
      out, = run_script(write_report([survivor("aabbccdd11223344", line: 5)]), SABOTEUR_HEAD_SHA: head)

      expect(out).to include("0 posted")
    end

    it "keeps the line when the base only changed lines below it" do
      out, = run_merged(edit(numbered(10), 3, "changed 3\n"), edit(numbered(10), 10, "base 10\n"), 3)

      expect(out).to include("1 posted")
      expect(posted_lines).to eq(["line=3"])
    end

    it "posts nothing and counts the finding when the base changed that line" do
      out, = run_merged(edit(numbered(10), 9, "changed 9\n"), edit(numbered(10), 2, "base 2\n"), 2)

      expect(out).to include("0 posted")
      expect(writes.map { |args| args[2] }).to eq(["POST"])
      expect(writes.first.find { |arg| arg.start_with?("body=") }).to include("1 more surviving mutant")
    end

    it "posts nothing for a checkout that is neither the head nor a merge of it" do
      checkout_head
      out, = run_script(write_report([survivor("aabbccdd11223344", line: 5)]), SABOTEUR_HEAD_SHA: "f" * 40)

      expect(out).to include("0 posted")
      expect(posted_lines.compact).to eq([])
    end

    it "posts nothing when the merge commit itself rewrote the line" do
      out, = run_merged(edit(numbered(10), 9, "changed 9\n"), "base 1\n#{numbered(10)}", 5,
                        evil: ->(text) { edit(text, 4, "resolved by hand\n") })

      expect(out).to include("0 posted")
      expect(posted_lines.compact).to eq([])
    end
  end
end
