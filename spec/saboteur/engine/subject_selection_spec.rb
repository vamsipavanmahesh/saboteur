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

  it "registers inline suppressions and warns with the parser's message for a broken file" do
    allow(Saboteur::InlineSuppression).to receive(:new).and_call_original
    diags = Saboteur::Engine::Diagnostics.new(StringIO.new)
    file = write("broken.rb", "def nope(\n")
    config = Saboteur::Config.new({}, root: @root)
    described_class.new(config, diags).select([file])
    expect(Saboteur::InlineSuppression).to have_received(:new).with(file, "def nope(\n")
    expect(diags.warnings).to include(a_string_matching(/broken\.rb does not parse: \S/))
  end

  it "finds every def in the files" do
    expect(select([write("cart.rb", source)]).map(&:id)).to eq(["Shop::Cart#total", "Shop::Cart.empty"])
  end

  it "stays quiet when a pattern matches one of several subjects in a file" do
    select([write("cart.rb", source)], subjects: ["Shop::Cart#total"])
    expect(diagnostics.warnings).to be_empty
  end

  it "selects a subject that matches any one of the patterns" do
    result = select([write("cart.rb", source)], subjects: ["Shop::Cart#total", "Nope#nope"])
    expect(result.map(&:id)).to eq(["Shop::Cart#total"])
  end

  it "warns for a subjectless changed file when the root is reached through a symlink" do
    Dir.mktmpdir do |link_base|
      link = File.join(link_base, "link")
      File.symlink(@root, link)
      note = File.join(link, "note.rb")
      File.write(note, "# just a comment\n")
      [%w[init -q], %w[add .], %w[commit -q -m base]].each do |args|
        Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: link)
      end
      File.write(note, "# just a comment\n# more\n")
      diags = Saboteur::Engine::Diagnostics.new(StringIO.new)
      config = Saboteur::Config.new({ "since" => "HEAD", "include" => ["**/*.rb"] }, root: link)
      described_class.new(config, diags).select([note])
      expect(diags.warnings).to include(a_string_matching(/have no subjects covering the changed lines/))
    end
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

    it "scopes the diff to the selected files and reports through the run diagnostics" do
      file = commit_base(two_methods)
      allow(Saboteur::Selection::GitDiff).to receive(:changed_lines).and_call_original
      select([file], since: "HEAD")
      expect(Saboteur::Selection::GitDiff).to have_received(:changed_lines)
        .with("HEAD", root: @root, include: [file].to_set, diagnostics: diagnostics)
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

  describe "--since when a changed Ruby file is excluded by c.exclude (#282)" do
    def commit_all
      [%w[init -q], %w[add .], %w[commit -q -m base]].each do |args|
        Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: @root)
      end
    end

    it "warns and names the changed file that c.exclude removes from the include territory" do
      cart = write("cart.rb", source)
      write("note.rb", "class Note\n  def text = \"n\"\nend\n")
      commit_all
      File.write(cart, source.sub("def total = 1", "def total = 2"))

      select([], since: "HEAD", include: ["*.rb"], exclude: ["cart.rb"])

      expect(diagnostics.warnings.size).to eq(1)
      expect(diagnostics.warnings.first).to include("--since: 1 changed Ruby file(s) are covered by c.include " \
                                                    "but removed by c.exclude, so nothing is mutated from " \
                                                    "them: cart.rb")
      expect(diagnostics.warnings.first).not_to include("...")
    end

    # --subject only filters subjects inside the files left after excludes,
    # so it cannot recover an excluded file; a positional operand clears
    # configured excludes (cli.rb's use_explicit_sources sets exclude: []).
    it "names an untracked new file that c.include covers but c.exclude removes" do
      write("cart.rb", source)
      write("note.rb", "class Note\n  def text = \"n\"\nend\n")
      commit_all
      File.write(File.join(@root, "fresh.rb"), "class Fresh\n  def new = 1\nend\n")

      select([], since: "HEAD", include: ["*.rb"], exclude: ["fresh.rb"])

      expect(diagnostics.warnings.size).to eq(1)
      expect(diagnostics.warnings.first).to include("them: fresh.rb")
    end

    it "advises narrowing c.exclude or a positional operand, never --subject" do
      cart = write("cart.rb", source)
      commit_all
      File.write(cart, source.sub("def total = 1", "def total = 2"))

      select([], since: "HEAD", include: ["*.rb"], exclude: ["cart.rb"])

      warning = diagnostics.warnings.first
      expect(warning).to include("Narrow or remove the c.exclude entry",
                                 "pass the file as a positional source operand")
      expect(warning).to end_with("(configured excludes are then ignored).")
      expect(warning).not_to include("--subject")
    end

    it "stays quiet when the changed file sits in the territory and is not excluded" do
      cart = write("cart.rb", source)
      write("other.rb", "class Other\n  def x = 1\nend\n")
      commit_all
      File.write(cart, source.sub("def total = 1", "def total = 2"))

      select([cart, File.join(@root, "other.rb")], since: "HEAD", include: ["*.rb"], exclude: ["other.rb"])

      expect(diagnostics.warnings).to be_empty
    end

    it "stays quiet when c.exclude removes only a changed non-Ruby file" do
      cart = write("cart.rb", source)
      readme = write("README.md", "hi\n")
      commit_all
      File.write(readme, "hello\n")

      select([cart], since: "HEAD", include: ["*"], exclude: ["README.md"])

      expect(diagnostics.warnings).to be_empty
    end

    it "names at most five excluded files, with an ellipsis for the rest" do
      files = (1..6).map { |n| write("f#{n}.rb", "class F#{n}\n  def x = 1\nend\n") }
      commit_all
      files.each_with_index { |file, n| File.write(file, "class F#{n + 1}\n  def x = 2\nend\n") }

      select([], since: "HEAD", include: ["*.rb"], exclude: ["f*.rb"])

      expect(diagnostics.warnings.size).to eq(1)
      warning = diagnostics.warnings.first
      expect(warning).to include("--since: 6 changed Ruby file(s) are covered by c.include")
      expect(warning).to include("from them: f1.rb, f2.rb, f3.rb, f4.rb, f5.rb, ...")
      expect(warning).not_to include("f6.rb")
    end

    # Dogfood survivor at 79fdbf59: dropping .sort was invisible while every
    # fixture's glob order already matched the sorted order. Concatenating
    # include patterns pins an unsorted territory order (Array#& keeps the
    # receiver's order), so the sorted assertion fails without .sort.
    it "sorts the named excluded files even when the include order is unsorted" do
      files = [write("zeta.rb", "class Zeta\n  def x = 1\nend\n"),
               write("mid.rb", "class Mid\n  def x = 1\nend\n"),
               write("alpha.rb", "class Alpha\n  def x = 1\nend\n")]
      commit_all
      files.each { |file| File.write(file, File.read(file).sub("def x = 1", "def x = 2")) }

      select([], since: "HEAD", include: ["z*.rb", "*.rb"], exclude: ["*.rb"])

      expect(diagnostics.warnings.size).to eq(1)
      expect(diagnostics.warnings.first).to include("them: alpha.rb, mid.rb, zeta.rb")
    end

    it "lists five excluded files in full, without an ellipsis" do
      files = (1..5).map { |n| write("g#{n}.rb", "class G#{n}\n  def x = 1\nend\n") }
      commit_all
      files.each_with_index { |file, n| File.write(file, "class G#{n + 1}\n  def x = 2\nend\n") }

      select([], since: "HEAD", include: ["*.rb"], exclude: ["g*.rb"])

      expect(diagnostics.warnings.size).to eq(1)
      warning = diagnostics.warnings.first
      expect(warning).to include("--since: 5 changed Ruby file(s)")
      expect(warning).to include("g1.rb, g2.rb, g3.rb, g4.rb, g5.rb")
      expect(warning).not_to include("...")
    end
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
      expect(diagnostics.warnings.first).to end_with("The file may not parse, or every change may sit " \
                                                     "outside a method.")
      expect(diagnostics.warnings.first).not_to include("...")
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

    it "selects every subject of an untracked file, as fully changed (#295)" do
      committed = write("old.rb", "class Old\n  def x = 1\nend\n")
      commit_all
      fresh = write("fresh.rb", source)
      expect(select([committed, fresh], since: "HEAD").map(&:id)).to eq(["Shop::Cart#total", "Shop::Cart.empty"])
      expect(diagnostics.warnings).to be_empty
    end

    it "warns for an untracked file whose lines cover no subject (#295)" do
      committed = write("old.rb", "class Old\n  def x = 1\nend\n")
      commit_all
      fresh = write("fresh.rb", "KIND = :none\n")
      expect(select([committed, fresh], since: "HEAD")).to be_empty
      expect(diagnostics.warnings.size).to eq(1)
      expect(diagnostics.warnings.first).to include("--since: 1 changed Ruby file(s) have no subjects")
        .and include("fresh.rb")
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

    it "names at most five subjectless files, with an ellipsis for the rest" do
      files = (1..6).map { |n| write("f#{n}.rb", "class F#{n}\n  KIND = :a\n\n  def x = 1\nend\n") }
      commit_all
      files.each_with_index do |file, n|
        File.write(file, "class F#{n + 1}\n  KIND = :b\n\n  def x = 1\nend\n")
      end

      expect(select(files, since: "HEAD")).to be_empty
      expect(diagnostics.warnings.size).to eq(1)
      warning = diagnostics.warnings.first
      expect(warning).to include("--since: 6 changed Ruby file(s) have no subjects")
      expect(warning).to include("from them: f1.rb, f2.rb, f3.rb, f4.rb, f5.rb, ...")
      expect(warning).not_to include("f6.rb")
    end

    it "lists five subjectless files in full, without an ellipsis" do
      files = (1..5).map { |n| write("g#{n}.rb", "class G#{n}\n  KIND = :a\n\n  def x = 1\nend\n") }
      commit_all
      files.each_with_index do |file, n|
        File.write(file, "class G#{n + 1}\n  KIND = :b\n\n  def x = 1\nend\n")
      end

      expect(select(files, since: "HEAD")).to be_empty
      expect(diagnostics.warnings.size).to eq(1)
      expect(diagnostics.warnings.first).to include("from them: g1.rb, g2.rb, g3.rb, g4.rb, g5.rb.")
      expect(diagnostics.warnings.first).not_to include("...")
    end

    it "never warns about a changed non-Ruby file, even one handed in the file list" do
      file = write("cart.rb", source)
      notes = write("NOTES.md", "hello\n")
      commit_all
      File.write(notes, "hello again\n")

      expect(select([file, notes], since: "HEAD")).to be_empty
      expect(diagnostics.warnings).to be_empty
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

  describe ".files_matching" do
    it "returns the files holding a matching subject, relative to root and sorted" do
      b = write("b.rb", "class Bee\n  def m\n    1\n  end\nend\n")
      a = write("a.rb", "class Ay\n  def m\n    1\n  end\nend\n")
      c = write("c.rb", "class Cee\n  def m\n    1\n  end\nend\n")
      expect(described_class.files_matching(@root, [c, b, a], ["Bee", "Ay#m"])).to eq(["a.rb", "b.rb"])
      expect(described_class.files_matching(@root, [c, a, b], ["Nope"])).to eq([])

      two = write("two.rb", "class Two\n  def m = 1\n  def n = 2\nend\n")
      expect(described_class.files_matching(@root, [two], ["Two#m"])).to eq(["two.rb"])
    end
  end
end
