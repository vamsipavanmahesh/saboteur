# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "open3"
require "stringio"
require "tmpdir"

# Non-UTF-8 locale regressions: every byte string crossing saboteur's
# boundary (git output, cache files, logs, worker pipes) must be re-tagged
# UTF-8, or LANG=C turns non-ASCII paths into crashes and empty selections.
RSpec.describe "non-UTF-8 locale boundaries" do
  # APFS and some other filesystems reject filenames that are not valid
  # UTF-8 at creation time; the raw-byte cases cannot run there.
  def binwrite_raw(path, text)
    File.binwrite(path, text)
  rescue Errno::EILSEQ
    skip "this filesystem rejects filenames that are not valid UTF-8"
  end

  def git_repo
    Dir.mktmpdir do |dir|
      git = lambda { |*args|
        Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
      }
      git.call("init", "-q")
      yield dir, git
    end
  end

  it "canary watches non-ASCII tracked files under a US-ASCII locale" do
    git_repo do |dir, git|
      File.write(File.join(dir, "café.md"), "x")
      git.call("add", ".")
      with_default_external(Encoding::US_ASCII) do
        canary = Saboteur::Engine::Canary.new(dir)
        File.delete(File.join(dir, "café.md"))
        expect { canary.check! }.to raise_error(Saboteur::CanaryTripped, /caf/)
      end
    end
  end

  it "--since selects non-ASCII changed files under a US-ASCII locale" do
    git_repo do |dir, git|
      File.write(File.join(dir, "héllo.rb"), "1\n")
      git.call("add", ".")
      git.call("commit", "-q", "-m", "base")
      File.write(File.join(dir, "héllo.rb"), "2\n")
      changed = with_default_external(Encoding::US_ASCII) do
        Saboteur::Selection::GitDiff.changed_lines("HEAD", root: dir)
      end
      expect(changed.keys.map { |path| path.delete_prefix("#{File.realpath(dir)}/") }).to eq(["héllo.rb"])
    end
  end

  it "loads a coverage map with non-ASCII paths under a US-ASCII locale" do
    Dir.mktmpdir do |dir|
      map = Saboteur::Selection::CoverageMap.new(lines: { "/repo/héllo.rb" => { 3 => %w[t1] } }, tests: %w[t1])
      path = File.join(dir, "coverage.json")
      File.write(path, map.to_json)
      loaded = with_default_external(Encoding::US_ASCII) { Saboteur::Selection::CoverageMap.load(path) }
      expect(loaded.tests).to eq(%w[t1])
    end
  end

  it "loads a result cache with non-ASCII keys under a US-ASCII locale" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "results.json")
      entries = { "héllo.rb#greet 0123456789abcdef" => { "status" => "killed", "killed_by" => [] } }
      File.write(path, JSON.generate(format: Saboteur::Engine::ResultCache::FORMAT, entries: entries))
      loaded = with_default_external(Encoding::US_ASCII) do
        Saboteur::Engine::ResultCache.new(path: path, root: dir, inputs: "config-1")
      end
      expect(loaded.instance_variable_get(:@entries).keys.first).to include("héllo.rb")
    end
  end

  it "excerpts baseline logs with non-ASCII content under a US-ASCII locale" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".saboteur"))
      File.binwrite(File.join(dir, ".saboteur", "baseline-1.log"), "Failure in ./spec/héllo_spec.rb\n")
      config = Saboteur::Config.new({ "seed" => 1 }, root: dir)
      guard = Saboteur::Engine::BaselineGuard.new(config: config, integration: nil, hooks: Saboteur::Hooks.new,
                                                  supervisor: nil, diagnostics: nil)
      excerpt = with_default_external(Encoding::US_ASCII) { guard.send(:failure_excerpt, 1) }
      expect(excerpt).to include("llo_spec.rb")
    end
  end

  it "parses worker result lines with non-ASCII content under a US-ASCII locale" do
    line = JSON.generate("file" => "lib/héllo.rb").force_encoding(Encoding::US_ASCII)
    pool = Saboteur::Execution::WorkerPool.new(jobs: 1)
    parsed = with_default_external(Encoding::US_ASCII) { pool.send(:parse, line) }
    expect(parsed["file"]).to eq("lib/héllo.rb")
  end

  it "parses protocol events with non-ASCII payloads under a US-ASCII locale" do
    io = StringIO.new
    Saboteur::Execution::Protocol.emit(io, :result, file: "lib/héllo.rb")
    payload = io.string.force_encoding(Encoding::US_ASCII)
    events = with_default_external(Encoding::US_ASCII) { Saboteur::Execution::Protocol.parse(payload) }
    expect(events.first["file"]).to eq("lib/héllo.rb")
  end

  # A tracked file whose name is not valid UTF-8 must stay in the watch:
  # scrubbing its bytes would make the existence probe fail and its later
  # deletion invisible.
  it "canary watches a tracked file whose name is not valid UTF-8, and sees its deletion" do
    git_repo do |dir, git|
      raw = "raw-\xFF.rb".b
      binwrite_raw(File.join(dir, raw), "x")
      File.write(File.join(dir, "café.md"), "x")
      git.call("add", ".")
      with_default_external(Encoding::US_ASCII) do
        canary = Saboteur::Engine::Canary.new(dir)
        expect { canary.check! }.not_to raise_error
        File.delete(File.join(dir, raw))
        expect { canary.check! }.to raise_error(Saboteur::CanaryTripped, /1 watched file/)
        File.delete(File.join(dir, "café.md"))
        expect { canary.check! }.to raise_error(Saboteur::CanaryTripped, /2 watched file/)
      end
    end
  end

  # core.quotePath is off for the diff, so the raw name bytes reach the
  # parser; identity must survive byte for byte.
  it "--since keeps the raw bytes of a changed file whose name is not valid UTF-8" do
    git_repo do |dir, git|
      raw = "raw-\xFF.rb".b
      binwrite_raw(File.join(dir, raw), "1\n")
      git.call("add", ".")
      git.call("commit", "-q", "-m", "base")
      binwrite_raw(File.join(dir, raw), "2\n")
      changed = with_default_external(Encoding::US_ASCII) do
        Saboteur::Selection::GitDiff.changed_lines("HEAD", root: dir)
      end
      expect(changed.keys.map { |path| File.basename(path) }).to eq([raw.dup.force_encoding(Encoding::UTF_8)])
      expect(changed.values.map(&:to_a)).to eq([[1]])
    end
  end

  # rev-parse --show-toplevel arrives tagged US-ASCII under LANG=C: joining
  # it with a UTF-8 relative path must not raise, and stripping the newline
  # must not either.
  it "--since joins a non-ASCII root and a non-ASCII changed file under a US-ASCII locale" do
    Dir.mktmpdir do |dir|
      root = File.join(dir, "pröj")
      FileUtils.mkdir_p(root)
      git = lambda { |*args|
        Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: root)
      }
      git.call("init", "-q")
      File.write(File.join(root, "héllo.rb"), "1\n")
      git.call("add", ".")
      git.call("commit", "-q", "-m", "base")
      File.write(File.join(root, "héllo.rb"), "2\n")
      changed = with_default_external(Encoding::US_ASCII) do
        Saboteur::Selection::GitDiff.changed_lines("HEAD", root: root)
      end
      expect(changed.keys).to eq([File.join(File.realpath(root), "héllo.rb")])
      expect(changed.values.map(&:to_a)).to eq([[1]])
    end
  end

  # JSON boundaries reject invalid bytes instead of scrubbing them into a
  # different payload that then parses fine.
  it "rejects a result cache whose bytes are not valid UTF-8" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "results.json")
      File.binwrite(path, %({"format": #{Saboteur::Engine::ResultCache::FORMAT}, "entries": {"bad-\xFF": {}}}).b)
      loaded = with_default_external(Encoding::US_ASCII) do
        Saboteur::Engine::ResultCache.new(path: path, root: dir, inputs: "config-1")
      end
      expect(loaded.instance_variable_get(:@entries)).to eq({})
    end
  end

  it "rejects a coverage map whose bytes are not valid UTF-8" do
    Dir.mktmpdir do |dir|
      map = Saboteur::Selection::CoverageMap.new(lines: { "/repo/héllo.rb" => { 3 => %w[t1] } }, tests: %w[t1])
      path = File.join(dir, "coverage.json")
      File.binwrite(path, map.to_json.b.sub("héllo".b, "bad-\xFF".b))
      loaded = with_default_external(Encoding::US_ASCII) { Saboteur::Selection::CoverageMap.load(path) }
      expect(loaded).to be_nil
    end
  end

  # One complete corrupt object on its own line; the valid event after it
  # must survive, so only the unreadable line is dropped.
  it "skips a protocol line whose bytes are not valid UTF-8" do
    corrupt = %({"v": 1, "event": "result", "file": "bad-\xFF.rb"}\n).b
    valid = %({"v": 1, "event": "beat", "file": "ok.rb"}\n)
    payload = "#{corrupt}#{valid}"
    events = with_default_external(Encoding::US_ASCII) { Saboteur::Execution::Protocol.parse(payload) }
    expect(events).to eq([{ "v" => 1, "event" => "beat", "file" => "ok.rb" }])
  end

  it "reports a worker result line whose bytes are not valid UTF-8 as unreadable" do
    line = %({"file": "bad-\xFF.rb", "status": "killed"}).b
    pool = Saboteur::Execution::WorkerPool.new(jobs: 1)
    parsed = with_default_external(Encoding::US_ASCII) { pool.send(:parse, line) }
    expect(parsed["error"]).to include("unreadable result from worker")
  end
end
