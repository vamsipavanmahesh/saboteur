# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "pathname"

# The summarized ERB-skip note (#372): one note per run, one entry per
# file, and the note names the root-relative path.
RSpec.describe Saboteur::Engine::Diagnostics, "ERB template skip note (#372)" do
  let(:err) { StringIO.new }
  let(:diagnostics) { described_class.new(err) }
  let(:file) { "/app/lib/generators/model/templates/model.rb" }

  it "starts with the note flag down, so the first skip emits the note" do
    expect(diagnostics.instance_variable_get(:@erb_template_note_emitted)).to be(false)
  end

  it "names the root-relative path in the note, whatever path-like object arrives" do
    diagnostics.record_erb_template_skip(Pathname.new(file), root: "/app")
    expect(diagnostics.warnings.join).to include("for example lib/generators/model/templates/model.rb")
    expect(diagnostics.warnings.join).not_to include("for example /app/")
    expect(diagnostics.warnings.join).not_to include("for example /lib/")
  end

  it "emits the note once and records a repeated file once" do
    2.times { diagnostics.record_erb_template_skip(file, root: "/app") }
    expect(diagnostics.warnings.join.scan("skipping ERB template files").size).to eq(1)
    expect(diagnostics.instance_variable_get(:@erb_template_skips)).to eq(["lib/generators/model/templates/model.rb"])
  end
end
