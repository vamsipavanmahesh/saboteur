# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Execution::Reevaluator, "method_added hooks" do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    ensure
      Object.send(:remove_const, :PinRe4) if Object.const_defined?(:PinRe4, false)
    end
  end

  def load_subjects(code)
    @path = File.join(@dir, "pin_re4.rb")
    File.write(@path, code)
    load @path
    Saboteur::SubjectFinder.new.call(@path).subjects.to_h { |s| [s.id, s] }
  end

  %w[nesting class_eval].each do |strategy|
    it "fires method_added once for the redefined method only, with #{strategy}" do
      code = "class PinRe4\n  def self.events = (@events ||= [])\n  " \
             "def self.method_added(name) = events << name\n  def foo = 1\nend\n"
      subject = load_subjects(code).fetch("PinRe4#foo")
      PinRe4.events.clear
      described_class.new(strategy).call(subject, subject.source.sub("1", "2"))
      expect(PinRe4.events).to eq([:foo])
    end
  end
end
