# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

RSpec.describe Saboteur::CLI, "pr budget (#654)" do
  [[], ["--max-duration-ok"]].each do |flags|
    it "reports the shortfall with #{flags.empty? ? 'a failing default' : 'explicit budget acceptance'}" do
      out = StringIO.new
      err = StringIO.new
      stop = Saboteur::EarlyStop.new(reason: "max_duration", unreached: [],
                                     truncated: [{ subject: person_subject.id, omitted: 2 }], unverified: [],
                                     planned_mutants: 3)
      report = Saboteur::Report.new(results: [result_for(:killed)], subjects: [person_subject],
                                    root: File.dirname(person_subject.file), wall_time: 1, early_stop: stop)
      allow(Saboteur::Engine).to receive(:new).and_return(
        engine_double(guessed_tests: nil, call: report)
      )
      # The engine is stubbed, but pr still validates its range before boot.
      # CI checkouts have no local "main" branch, so the ref check is stubbed too.
      allow(Saboteur::Selection::GitDiff).to receive(:verify_ref!).with("main", root: anything)
      allow(Saboteur::Selection::GitDiff).to receive(:changed_paths)
        .with("main", root: anything).and_return(present: ["lib/probe.rb"], deleted: [])
      command = described_class.new(["pr", *flags], out:, err:)
      expect(command.call).to eq(flags.empty? ? 4 : 0)
      expect(out.string).to include("partial: 2 of 3 mutants not run")
    end
  end
end
