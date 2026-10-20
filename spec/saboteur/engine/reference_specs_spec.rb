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
    described_class.new(root, ->(_file) { constants.map { |name| constant(name) } }).call([file], specs).chosen
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
    found = described_class.new(root, ->(_file) { [constant("Widget")] }).call([file], names)
    expect([found.chosen, found.crowded]).to eq([{}, file => names.size])
  end

  describe "specs that require the file" do
    let(:file) { "lib/jwt/widget.rb" }

    def readers_for(source, text, path: "spec/features/a_spec.rb")
      write_spec(path, text)
      described_class.new(root, ->(_file) { [] }).call([source], [path]).chosen
    end

    def requirers(text, path: "spec/features/a_spec.rb")
      write_spec(path, text)
      readers([path], constants: [])
    end

    it "takes require_relative by path, with or without .rb and in either quote" do
      expect(requirers("require_relative \"../../lib/jwt/widget\"\n")).to eq(file => ["spec/features/a_spec.rb"])
      expect(requirers("require_relative '../../lib/jwt/widget.rb'\n")).to eq(file => ["spec/features/a_spec.rb"])
    end

    it "takes require by load path from the source root, with parens or not" do
      expect(requirers("require \"jwt/widget\"\n")).to eq(file => ["spec/features/a_spec.rb"])
      expect(requirers("  require('jwt/widget.rb')\n")).to eq(file => ["spec/features/a_spec.rb"])
    end

    it "allows extra spaces between the require and its path" do
      expect(requirers("require   \"jwt/widget\"\n")).to eq(file => ["spec/features/a_spec.rb"])
      expect(requirers("require( \"jwt/widget\")\n")).to eq(file => ["spec/features/a_spec.rb"])
    end

    it "skips a spec it cannot read", skip: Process.uid.zero? && "root reads any file" do
      path = "spec/features/a_spec.rb"
      write_spec(path, "require \"jwt/widget\"\n")
      File.chmod(0o000, File.join(root, path))

      expect(readers([path], constants: [])).to eq({})
    ensure
      File.chmod(0o644, File.join(root, path))
    end

    it "ignores a commented require and one that names the root-relative path or a basename" do
      expect(requirers("# require \"jwt/widget\"\n")).to eq({})
      expect(requirers("require \"lib/jwt/widget\"\n")).to eq({})
      expect(requirers("require \"widget\"\n")).to eq({})
    end

    it "ignores a require_relative that resolves to another file" do
      expect(requirers("require_relative \"../lib/jwt/widget\"\n")).to eq({})
    end

    it "does not take a require from a load path as a relative path, or the reverse" do
      expect(requirers("require_relative \"jwt/widget\"\n")).to eq({})
      expect(requirers("require \"../../lib/jwt/widget\"\n")).to eq({})
    end

    it "strips only a leading directory name to get the load path" do
      expect(readers_for("lib/a/lib/b.rb", "require \"a/lib/b\"\n"))
        .to eq("lib/a/lib/b.rb" => ["spec/features/a_spec.rb"])
      expect(readers_for("lib/a/lib/b.rb", "require \"lib/b\"\n")).to eq({})
      expect(readers_for("src/jwt/x.rb", "require \"jwt/x\"\n"))
        .to eq("src/jwt/x.rb" => ["spec/features/a_spec.rb"])
    end

    it "gives a file that has no leading directory name no load path of its own" do
      expect(readers_for("/a/b.rb", "require \"a/b\"\nrequire \"/b\"\n")).to eq({})
    end

    it "reads a spec as UTF-8 whatever the default external encoding is" do
      original = Encoding.default_external
      Encoding.default_external = Encoding::US_ASCII
      expect(readers_for("lib/jwt/w\u00efdget.rb", "require \"jwt/w\u00efdget\"\n"))
        .to eq("lib/jwt/w\u00efdget.rb" => ["spec/features/a_spec.rb"])
    ensure
      Encoding.default_external = original
    end

    it "reads a spec with invalid bytes and still finds its require" do
      expect(requirers("\xFF\xFE\nrequire \"jwt/widget\"\n".b)).to eq(file => ["spec/features/a_spec.rb"])
    end

    it "counts a spec once when it requires the file and reads its constant" do
      write_spec("spec/features/a_spec.rb", "require \"jwt/widget\"\nWidget.new\n")

      expect(readers(["spec/features/a_spec.rb"])).to eq(file => ["spec/features/a_spec.rb"])
    end
  end
end
