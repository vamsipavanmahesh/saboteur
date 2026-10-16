# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::ConstantSubject do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  it "is a plain subject: no singleton, no sclass, no sig, empty consumer maps" do
    file = File.join(@root, "constants.rb")
    File.write(file, "MAP = { a: 1 }.freeze\n")
    subject = Saboteur::ConstantSubjectFinder.new.call(file).subjects.first

    expect(subject.singleton).to be(false)
    expect(subject.sclass).to be(false)
    expect(subject.sig_span).to be_nil
    expect(subject.consumer_lines).to eq({})
    expect(subject.consumer_defs).to eq({})
  end
end
