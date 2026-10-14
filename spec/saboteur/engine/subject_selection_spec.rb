# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require "stringio"
require "tmpdir"

RSpec.describe Saboteur::Engine::SubjectSelection do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:source) { "module Shop\n  class Cart\n    def total = 1\n    def self.empty = new\n  end\nend\n" }

  def write(name, text)
    File.join(@root, name).tap { |path| File.write(path, text) }
  end

  def select(files, **settings)
    config = Saboteur::Config.new(settings.transform_keys(&:to_s), root: @root)
    described_class.new(config, diagnostics).select(files)
  end

  it "finds every def in the files" do
    expect(select([write("cart.rb", source)]).map(&:id)).to eq(["Shop::Cart#total", "Shop::Cart.empty"])
  end

  it "keeps subjects matching --subject patterns, including namespace prefixes" do
    file = write("cart.rb", source)
    expect(select([file], subjects: ["Shop::Cart.empty"]).map(&:id)).to eq(["Shop::Cart.empty"])
    expect(select([file], subjects: ["Shop"]).size).to eq(2)
    expect(select([file], subjects: ["Sho"])).to be_empty
  end

  # Patterns are names, not globs: "Item*" matches nothing, and a silent
  # empty run looks like a clean one.
  it "warns about a --subject pattern that matches no subject" do
    select([write("cart.rb", source)], subjects: ["Shop::Cart", "Cart*"])
    expect(diagnostics.warnings).to eq(["--subject Cart* matches no subject (patterns are names like " \
                                        "Klass, Klass#meth or Klass.meth, not globs)"])
  end

  it "keeps only methods with a line changed since the ref" do
    file = write("cart.rb", source)
    git = lambda { |*args|
      Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: @root)
    }
    git.call("init", "-q")
    git.call("add", ".")
    git.call("commit", "-q", "-m", "base")
    File.write(file, source.sub("def total = 1", "def total = 2"))
    expect(select([file], since: "HEAD").map(&:id)).to eq(["Shop::Cart#total"])
  end

  describe "--since with changes that leave a method's syntax alone" do
    let(:err) { StringIO.new }
    let(:diagnostics) { Saboteur::Engine::Diagnostics.new(err) }
    let(:two_methods) do
      "class Cart\n  def total\n    1 + 1\n  end\n\n  def count\n    2\n  end\nend\n"
    end

    def commit_base(text)
      file = write("cart.rb", text)
      [%w[init -q], %w[add .], %w[commit -q -m base]].each do |args|
        Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: @root)
      end
      file
    end

    it "skips a method changed only by a comment or spacing, and says so" do
      file = commit_base(two_methods)
      File.write(file, two_methods.sub("1 + 1", "1+1 # one").sub("    2\n", "\n    2\n"))

      expect(select([file], since: "HEAD")).to be_empty
      expect(err.string).to eq("saboteur: 2 changed method(s) differ only in comments or formatting, " \
                               "so they are skipped: Cart#total, Cart#count\n")
    end

    it "keeps the method whose code changed and skips the other" do
      file = commit_base(two_methods)
      File.write(file, two_methods.sub("1 + 1", "1 + 2").sub("    2\n", "    2 # two\n"))

      expect(select([file], since: "HEAD").map(&:id)).to eq(["Cart#total"])
      expect(err.string).to include("1 changed method(s) differ only in comments or formatting, so they are " \
                                    "skipped: Cart#count")
    end

    def commented_methods(count)
      text = (1..count).map { |n| "  def m#{n}\n    #{n}\n  end\n" }.join("\n")
      file = commit_base("class Cart\n#{text}end\n")
      File.write(file, File.read(file).gsub(/^    (\d)$/, "    \\1 # n"))
      select([file], since: "HEAD")
    end

    it "names every skipped method up to five" do
      expect(commented_methods(5)).to be_empty
      expect(err.string).to end_with("skipped: Cart#m1, Cart#m2, Cart#m3, Cart#m4, Cart#m5\n")
    end

    it "names five and then an ellipsis when more were skipped" do
      expect(commented_methods(6)).to be_empty
      expect(err.string).to include("6 changed method(s)").and end_with("Cart#m4, Cart#m5, ...\n")
    end

    it "does not look up the merge base when no method changed" do
      file = commit_base(two_methods)
      allow(Saboteur::Selection::GitDiff).to receive(:merge_base).and_call_original

      expect(select([file], since: "HEAD")).to be_empty
      expect(Saboteur::Selection::GitDiff).to have_received(:merge_base).once
    end

    it "says nothing when no method is skipped" do
      file = commit_base(two_methods)
      File.write(file, two_methods.sub("1 + 1", "1 + 2"))
      select([file], since: "HEAD")

      expect(err.string).to eq("")
    end

    it "refuses an unknown ref as a usage error" do
      file = commit_base(two_methods)

      expect { select([file], since: "no-such-ref") }.to raise_error(Saboteur::ConfigError, /--since no-such-ref/)
    end
  end

  it "keeps --since working when some selected files have no change" do
    changed = write("cart.rb", source)
    untouched = write("other.rb", "class Other\n  def x = 1\nend\n")
    git = lambda { |*args|
      Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: @root)
    }
    git.call("init", "-q")
    git.call("add", ".")
    git.call("commit", "-q", "-m", "base")
    File.write(changed, source.sub("def total = 1", "def total = 2"))
    expect(select([changed, untouched], since: "HEAD").map(&:id)).to eq(["Shop::Cart#total"])
  end

  it "records discovery failure only for the malformed member of a mixed file set" do
    broken = write("broken.rb", "class X; def ( ; end")
    valid = write("cart.rb", source)
    expect(select([broken, valid]).map(&:id)).to eq(["Shop::Cart#total", "Shop::Cart.empty"])
    expect(diagnostics.discovery_failures.map(&:to_h)).to eq([
                                                               { file: broken, reason: "invalid_file_syntax" }
                                                             ])
    expect(diagnostics.warnings.size).to eq(1)
  end

  it "reports only the first parse error of a file" do
    select([write("broken.rb", "class X\n  def (\n  def )\nend\n")])
    expect(diagnostics.warnings.size).to eq(1)
  end

  it "warns about files that do not parse and skips them" do
    expect(select([write("broken.rb", "class X\n  def (\nend\n")])).to be_empty
    expect(diagnostics.warnings.first).to start_with("broken.rb does not parse")
    expect(diagnostics.discovery_failures.map(&:to_h)).to eq([
                                                               { file: File.join(@root, "broken.rb"),
                                                                 reason: "invalid_file_syntax" }
                                                             ])
    expect(diagnostics.discovery_failures.first.file).to be_frozen
  end

  describe "--since when a changed Ruby file yields no subjects (#232)" do
    let(:err) { StringIO.new }
    let(:diagnostics) { Saboteur::Engine::Diagnostics.new(err) }

    def commit_all
      [%w[init -q], %w[add .], %w[commit -q -m base]].each do |args|
        Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: @root)
      end
    end

    it "warns when the changed lines sit outside every method" do
      file = write("cart.rb", "class Cart\n  KIND = :cart\n\n  def total = 1\nend\n")
      commit_all
      File.write(file, "class Cart\n  KIND = :shop\n\n  def total = 1\nend\n")

      expect(select([file], since: "HEAD")).to be_empty
      expect(diagnostics.warnings.size).to eq(1)
      expect(diagnostics.warnings.first).to include("--since: 1 changed Ruby file(s) have no subjects " \
                                                    "covering the changed lines, so nothing is mutated " \
                                                    "from them: cart.rb")
    end

    it "stays quiet when the diff touches no included Ruby file" do
      file = write("cart.rb", source)
      readme = write("README.md", "hi\n")
      commit_all
      File.write(readme, "hello\n")

      expect(select([file], since: "HEAD")).to be_empty
      expect(diagnostics.warnings).to be_empty
      expect(err.string).to eq("")
    end

    it "names only the changed file without subjects when another file matched" do
      cart = write("cart.rb", source)
      note = write("note.rb", "class Note\n  KIND = :note\n\n  def text = \"n\"\nend\n")
      commit_all
      File.write(cart, source.sub("def total = 1", "def total = 2"))
      File.write(note, "class Note\n  KIND = :memo\n\n  def text = \"n\"\nend\n")

      expect(select([cart, note], since: "HEAD").map(&:id)).to eq(["Shop::Cart#total"])
      expect(diagnostics.warnings.size).to eq(1)
      expect(diagnostics.warnings.first).to include("1 changed Ruby file(s)").and include("note.rb")
      expect(diagnostics.warnings.first).not_to include("cart.rb")
    end

    it "stays quiet when a --subject pattern, already warned about, filtered the subjects" do
      file = write("cart.rb", source)
      commit_all
      File.write(file, source.sub("def total = 1", "def total = 2"))

      expect(select([file], since: "HEAD", subjects: ["Other"])).to be_empty
      expect(diagnostics.warnings.size).to eq(1)
      expect(diagnostics.warnings.first).to include("--subject Other matches no subject")
    end
  end
end
