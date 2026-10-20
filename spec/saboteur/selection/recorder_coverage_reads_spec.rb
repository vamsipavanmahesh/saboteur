# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# The recorder reads Coverage only through CoverageReads (#564): a loaded
# class whose #hash is not an Integer makes the C call raise TypeError, and
# that must reach the user as a saboteur refusal, not an internal crash.
RSpec.describe Saboteur::Selection::Recorder, "coverage reads (#564)" do
  let(:file) { Saboteur::Selection::CoverageMap.canonical(__FILE__) }
  let(:recorder) { described_class.new([__FILE__]) }
  let(:type_error) { TypeError.new("can't convert Foo to Integer (Foo#hash gives String)") }

  def snapshot(lines: [nil, 1, 0, 2], path: __FILE__)
    { path => { lines: lines, branches: {} } }
  end

  describe "#start" do
    it "resumes a suspended Coverage, then clears it with a non-stopping read, in that order" do
      allow(Coverage).to receive(:state).and_return(:suspended)
      allow(Coverage).to receive(:resume)
      allow(Coverage).to receive(:result).with(stop: false, clear: true).and_return({ "a.rb" => {} })
      expect(recorder.start).to eq({ "a.rb" => {} })
      expect(Coverage).to have_received(:resume).ordered
      expect(Coverage).to have_received(:result).with(stop: false, clear: true).ordered
    end

    it "does not resume a Coverage that is already running" do
      allow(Coverage).to receive(:state).and_return(:running)
      allow(Coverage).to receive(:resume)
      allow(Coverage).to receive(:result).with(stop: false, clear: true).and_return({})
      recorder.start
      expect(Coverage).not_to have_received(:resume)
    end

    it "refuses with the generic TypeError diagnostic instead of crashing" do
      allow(Coverage).to receive(:state).and_return(:running)
      allow(Coverage).to receive(:result).and_raise(type_error)
      expect { recorder.start }.to raise_error(Saboteur::Error, /Coverage\.result raised TypeError \(can't convert Foo/)
    end
  end

  describe "per-test hits" do
    before do
      allow(Coverage).to receive(:result).with(stop: false, clear: true).and_return(snapshot)
      allow(Coverage).to receive(:running?).and_return(true)
      allow(Coverage).to receive(:state).and_return(:suspended)
      allow(Coverage).to receive(:suspend)
      allow(Coverage).to receive(:resume)
    end

    it "attributes the hit lines and the called method to the finished test" do
      calls = instance_double(Saboteur::MethodCalls, enable: nil, resume: nil)
      allow(calls).to receive(:pause).and_return(calls)
      allow(calls).to receive(:drain).and_return({ __FILE__ => Set[[3, :m]] }, {})
      allow(Saboteur::MethodCalls).to receive(:new).and_return(calls)
      recorder.test_started("t1", "spec/a_spec.rb")
      recorder.test_finished("t1")
      map = recorder.result
      expect(map.lines.fetch(file).transform_values(&:to_a)).to eq({ 2 => ["t1"], 4 => ["t1"] })
      expect(map.methods.fetch(file).transform_values(&:to_a)).to eq({ 3 => ["t1"] })
    end

    it "suspends Coverage while it reads each delta and resumes it afterwards" do
      recorder.test_started("t1", "spec/a_spec.rb")
      expect(Coverage).to have_received(:suspend).once.ordered
      expect(Coverage).to have_received(:resume).once.ordered
    end

    it "attributes a hit branch arm, and keeps an unhit arm out of the hits" do
      branches = { [:if, 0, 5, 2, 8, 5] => { [:then, 1, 6, 4, 6, 10] => 1, [:else, 2, 7, 4, 7, 8] => 0 } }
      allow(Coverage).to receive(:result).with(stop: false, clear: true)
                                         .and_return({ __FILE__ => { lines: [], methods: {}, branches: branches } })
      recorder.test_started("t1", "spec/a_spec.rb")
      recorder.test_finished("t1")
      arms = recorder.result.branches.fetch(file)
      expect(arms.fetch([6, 4, 6, 10]).to_a).to eq(["t1"])
      expect(arms.fetch([7, 4, 7, 8]).to_a).to eq([])
    end

    it "does not record an arm whose span is its branch's own span" do
      branches = { [:if, 0, 5, 2, 8, 5] => { [:then, 1, 5, 2, 8, 5] => 1 } }
      allow(Coverage).to receive(:result).with(stop: false, clear: true)
                                         .and_return({ __FILE__ => { lines: [], methods: {}, branches: branches } })
      recorder.test_started("t1", "spec/a_spec.rb")
      recorder.test_finished("t1")
      expect(recorder.result.branches.fetch(file, {})).not_to have_key([5, 2, 8, 5])
    end

    it "tolerates a coverage report without methods" do
      allow(Coverage).to receive(:result).with(stop: false, clear: true)
                                         .and_return({ __FILE__ => { lines: [nil, 1] } })
      expect { recorder.test_started("t2", "spec/a_spec.rb") }.not_to raise_error
      expect(recorder.result.methods).to be_empty
    end

    it "ignores files outside the recorded set" do
      allow(Coverage).to receive(:result).with(stop: false, clear: true).and_return(snapshot(path: "/elsewhere.rb"))
      recorder.test_started("t1", "spec/a_spec.rb")
      recorder.test_finished("t1")
      expect(recorder.result.lines).to be_empty
    end

    it "does not suspend or resume when Coverage is not running" do
      allow(Coverage).to receive(:running?).and_return(false)
      allow(Coverage).to receive(:state).and_return(:running)
      recorder.test_started("t1", "spec/a_spec.rb")
      expect(Coverage).not_to have_received(:suspend)
      expect(Coverage).not_to have_received(:resume)
    end

    it "reads with a clearing, non-stopping call in both hooks" do
      recorder.test_started("t1", "spec/a_spec.rb")
      recorder.test_finished("t1")
      expect(Coverage).to have_received(:result).with(stop: false, clear: true).twice
    end

    it "refuses with the TypeError diagnostic from a hook, and resumes nothing it never suspended" do
      allow(Coverage).to receive(:state).and_return(:running)
      allow(Coverage).to receive(:result).and_raise(type_error)
      expect { recorder.test_started("t1", "spec/a_spec.rb") }
        .to raise_error(Saboteur::Error, /Coverage\.result raised TypeError/)
      expect { recorder.test_finished("t1") }.to raise_error(Saboteur::Error, /Coverage\.result raised TypeError/)
      expect(Coverage).not_to have_received(:resume)
    end
  end
end
