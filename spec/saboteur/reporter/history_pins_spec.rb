# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "saboteur/reporter/history_record"
require "saboteur/reporter/history_paths"

RSpec.describe "score history pins" do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = File.realpath(dir)
      example.run
    end
  end

  def report
    report_of(result_for(:killed, kill_cause: "assertion"), result_for(:survived, replacement: "true"))
  end

  def history
    Saboteur::Reporter::ScoreHistory.new(File.join(@dir, "h.jsonl"))
  end

  def row
    history.send(:build, report, "a" * 40, {})
  end

  describe Saboteur::Reporter::HistoryRecord do
    it "checks both fractions" do
      %w[score coveredScore].each do |key|
        expect { described_class.validate(row.merge(key => 2)) }
          .to raise_error(Saboteur::Error, "score history contains an invalid score"), key
      end
    end

    it "gives the parser's reason after an invalid date" do
      ["garbage", nil, 5].each do |value|
        expect { described_class.validate(row.merge("date" => value)) }
          .to raise_error(Saboteur::Error, /\Ascore history contains an invalid date: .+/), value.inspect
      end
    end
  end

  describe Saboteur::Reporter::HistoryPaths do
    it "accepts different files and refuses two names for one file" do
      one = File.join(@dir, "one")
      two = File.join(@dir, "two")
      File.write(one, "")
      File.write(two, "")
      expect { described_class.validate([one, two, nil]) }.not_to raise_error
      File.link(one, File.join(@dir, "link"))
      expect { described_class.validate([one, File.join(@dir, "link")]) }
        .to raise_error(Saboteur::Error, "score history/report destinations alias the same file")
    end

    it "tells files apart by device as well as inode number" do
      one = File.join(@dir, "one")
      two = File.join(@dir, "two")
      File.write(one, "")
      File.write(two, "")
      real = File.method(:stat)
      allow(File).to receive(:stat) do |path|
        stat = real.call(path)
        instance_double(File::Stat, file?: true, ino: 7, dev: path == one ? 1 : 2, class: stat.class)
      end
      expect { described_class.validate([one, two]) }.not_to raise_error
    end

    it "expands a home-relative path before comparing" do
      File.write(File.join(@dir, "f"), "")
      previous = ENV.to_h.fetch("HOME", nil)
      ENV["HOME"] = @dir
      expect { described_class.validate(["~/f", File.join(@dir, "f")]) }
        .to raise_error(Saboteur::Error, /alias the same file/)
    ensure
      ENV["HOME"] = previous
    end

    it "says why a path cannot be verified" do
      path = File.join(@dir, "f")
      File.write(path, "")
      allow(File).to receive(:stat).and_call_original
      allow(File).to receive(:stat).with(path).and_raise(Errno::EACCES)
      expect { described_class.validate([path]) }
        .to raise_error(Saboteur::Error, %r{\Ascore history/report paths cannot be verified: .*Permission denied})
    end
  end

  describe Saboteur::Reporter::ScoreHistory do
    it "does not let the order of the scope or of the results change the digests" do
      one = report_of(result_for(:killed, kill_cause: "assertion"), result_for(:survived, replacement: "true"))
      two = report_of(result_for(:survived, replacement: "true"), result_for(:killed, kill_cause: "assertion"))
      first = history.send(:build, one, "a" * 40, { "b" => 1, "a" => 2 })
      second = history.send(:build, two, "a" * 40, { "a" => 2, "b" => 1 })
      expect(first.values_at("selection", "inventory")).to eq(second.values_at("selection", "inventory"))
    end

    [KeyError.new("boom"), TypeError.new("boom"), JSON::ParserError.new("boom")].each do |error|
      it "reports a #{error.class} while recording as a hard error with its reason" do
        store = history
        allow(store).to receive(:build).and_raise(error)
        expect { store.append(report, head: "a" * 40, scope: {}) }
          .to raise_error(Saboteur::Error, "score history was not recorded: boom")
      end
    end

    it "puts the system error in the message when an existing history cannot be read" do
      path = File.join(@dir, "h.jsonl")
      File.write(path, "")
      File.chmod(0o000, path)
      skip "permission bits are ignored for this user" if File.readable?(path)
      expect { described_class.new(path).validate_existing }
        .to raise_error(Saboteur::Error, /\Ascore history cannot be read: .*Permission denied/)
    ensure
      File.chmod(0o600, path)
    end
  end
end
