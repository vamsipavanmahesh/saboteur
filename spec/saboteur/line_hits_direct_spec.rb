# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# The tracer callbacks run inside a TracePoint hook, where Coverage cannot see
# them, so saboteur's own map has no test for them. These examples call them
# directly, outside any hook, and pin the same behavior.
RSpec.describe Saboteur::LineHits, "callbacks called directly" do
  let(:event) { Struct.new(:path, :lineno) }

  def hits_of(tracker, clear: false)
    tracker.drain(clear: clear).transform_values(&:to_a)
  end

  describe "#record" do
    it "records the line of a wanted file" do
      tracker = described_class.new(["/a.rb"])
      tracker.send(:record, event.new("/a.rb", 3))
      tracker.send(:record, event.new("/a.rb", 3))
      tracker.send(:record, event.new("/a.rb", 5))
      expect(hits_of(tracker)).to eq("/a.rb" => [3, 5])
    end

    it "skips a file that is not wanted, and records every file when none are given" do
      tracker = described_class.new(["/a.rb"])
      tracker.send(:record, event.new("/b.rb", 1))
      expect(hits_of(tracker)).to eq({})
      everything = described_class.new
      everything.send(:record, event.new("/b.rb", 1))
      expect(hits_of(everything)).to eq("/b.rb" => [1])
    end

    it "skips a line while paused" do
      tracker = described_class.new.pause
      tracker.send(:record, event.new("/a.rb", 1))
      expect(hits_of(tracker)).to eq({})
    end

    it "reports the first failure when several happen before the drain" do
      calls = 0
      tracker = described_class.new(["/a.rb"], canonical: ->(_path) { raise IOError, "failure #{calls += 1}" })
      tracker.send(:record, event.new("/a.rb", 1))
      tracker.send(:record, event.new("/b.rb", 1))
      expect { tracker.drain }.to raise_error(IOError, "failure 1")
    end

    it "keeps a failure for drain instead of raising it into the traced code" do
      tracker = described_class.new(["/a.rb"], canonical: ->(_path) { raise IOError, "boom" })
      expect { tracker.send(:record, event.new("/a.rb", 1)) }.not_to raise_error
      expect { tracker.drain }.to raise_error(IOError, "boom")
    end
  end

  describe "#wanted?" do
    let(:files) { ["/a.rb"] }

    def wanted(path, canonical = ->(file) { file })
      described_class.new.send(:wanted?, files, canonical, path)
    end

    it "is true for a file in the set and false for one outside it" do
      expect(wanted("/a.rb")).to be(true)
      expect(wanted("/b.rb")).to be(false)
    end

    it "matches the canonical form of the path" do
      expect(wanted("/x/../a.rb", ->(file) { file.sub("/x/..", "") })).to be(true)
    end

    it "is false when the canonicalizer refuses the path" do
      [ArgumentError, Errno::ENOENT, TypeError].each do |error|
        expect(wanted("/a.rb", ->(_file) { raise error })).to be(false)
      end
    end

    it "does not swallow other errors" do
      expect { wanted("/a.rb", ->(_file) { raise IOError }) }.to raise_error(IOError)
    end
  end
end
