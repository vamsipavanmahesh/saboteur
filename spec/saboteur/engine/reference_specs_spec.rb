# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Engine::ReferenceSpecs do
  let(:root) { File.realpath(Dir.mktmpdir("saboteur-refspecs")) }
  let(:file) { "lib/widget.rb" }

  after { FileUtils.remove_entry(root) }

  def write_spec(path, text)
    FileUtils.mkdir_p(File.dirname(File.join(root, path)))
    File.write(File.join(root, path), text)
  end

  def constant(name)
    Saboteur::Engine::TestGuess::DefinedConstant.new(name: name.to_sym, owner: nil, id: name)
  end

  def readers(specs, constants: ["Widget"])
    described_class.new(root, ->(_file) { constants.map { |name| constant(name) } }).call([file], specs)
  end

  it "returns the readers sorted, whatever order the suite lists them in" do
    write_spec("spec/b_spec.rb", "Widget.new\n")
    write_spec("spec/a_spec.rb", "Widget.new\n")

    expect(readers(%w[spec/b_spec.rb spec/a_spec.rb])).to eq(file => %w[spec/a_spec.rb spec/b_spec.rb])
  end

  it "names a spec once when it reads two of the file's constants" do
    write_spec("spec/a_spec.rb", "Widget.new\nGadget.new\n")

    expect(readers(%w[spec/a_spec.rb], constants: %w[Widget Gadget])).to eq(file => %w[spec/a_spec.rb])
  end

  it "skips a symlinked spec, which may point outside the project" do
    outside = File.join(root, "outside.rb")
    File.write(outside, "Widget.new\n")
    FileUtils.mkdir_p(File.join(root, "spec"))
    File.symlink(outside, File.join(root, "spec", "linked_spec.rb"))

    expect(readers(%w[spec/linked_spec.rb])).to eq({})
  end

  it "skips a spec file that does not exist" do
    expect(readers(%w[spec/gone_spec.rb])).to eq({})
  end

  it "keeps a file read by exactly the cap and drops one read by more" do
    names = Array.new(described_class::CAP + 1) { |n| format("spec/r%02d_spec.rb", n) }
    names.each { |path| write_spec(path, "Widget.new\n") }

    expect(readers(names.first(described_class::CAP))).to eq(file => names.first(described_class::CAP))
    expect(readers(names)).to eq({})
  end
end
