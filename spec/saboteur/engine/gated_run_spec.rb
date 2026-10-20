# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Engine::GatedRun do
  let(:diagnostics) { instance_double(Saboteur::Engine::Diagnostics, inform: nil, announce: nil) }
  let(:host) do
    diagnostics = self.diagnostics
    Class.new do
      include Saboteur::Engine::GatedRun

      define_method(:initialize) { @diagnostics = diagnostics }
      def config = { "since" => nil }
      def inform_skipped_specs(_guess); end
      def stop_or_warn_unmapped(_guess); end
      public :report_unmapped
    end.new
  end

  def guess(referenced)
    instance_double(Saboteur::Engine::TestGuess::Result, subjectless: [], referenced: referenced,
                                                         referenced_message: "the note")
  end

  it "announces the by-reference note when one file was chosen that way" do
    host.report_unmapped(guess("lib/a.rb" => ["spec/a_spec.rb"]))

    expect(diagnostics).to have_received(:announce).with("the note")
  end

  it "announces it once when two files were" do
    host.report_unmapped(guess("lib/a.rb" => ["spec/a_spec.rb"], "lib/b.rb" => ["spec/b_spec.rb"]))

    expect(diagnostics).to have_received(:announce).with("the note").once
  end

  it "says nothing when no file was chosen by reference" do
    host.report_unmapped(guess({}))

    expect(diagnostics).not_to have_received(:announce)
  end
end
