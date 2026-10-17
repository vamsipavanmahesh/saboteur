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

  def select(files, test_files: nil, **settings)
    config = Saboteur::Config.new(settings.transform_keys(&:to_s), root: @root)
    described_class.new(config, diagnostics, test_files: test_files).select(files)
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

  # Past five skipped files the note stays readable: the count and the
  # first five ids, then an ellipsis (#369 review dogfood).
  it "names the count and first five ids when six files are intentionally untested" do
    FileUtils.mkdir_p(File.join(@root, "config"))
    entries = (1..6).map { |i| "  \"f#{i}.rb\" => []" }.join(",\n")
    write("config/saboteur_custom_map.rb", "SABOTEUR_CUSTOM_MAP = {\n#{entries}\n}.freeze\n")
    io = StringIO.new
    diags = Saboteur::Engine::Diagnostics.new(io)
    files = (1..6).map { |i| write("f#{i}.rb", "module M#{i}\n  def self.m = 1\nend\n") }
    config = Saboteur::Config.new({}, root: @root)

    expect(described_class.new(config, diags).select(files)).to eq([])
    expect(io.string).to include("6 subject(s) skipped: intentionally untested in config/saboteur_custom_map.rb: " \
                                 "M1.m, M2.m, M3.m, M4.m, M5.m, ...")
    expect(io.string).not_to include("M6.m")
  end

  # Below five every id fits as well: no ellipsis, and the count matches.
  it "lists every id without an ellipsis at three skipped subjects" do
    FileUtils.mkdir_p(File.join(@root, "config"))
    entries = (1..3).map { |i| "  \"f#{i}.rb\" => []" }.join(",\n")
    write("config/saboteur_custom_map.rb", "SABOTEUR_CUSTOM_MAP = {\n#{entries}\n}.freeze\n")
    io = StringIO.new
    diags = Saboteur::Engine::Diagnostics.new(io)
    files = (1..3).map { |i| write("f#{i}.rb", "module M#{i}\n  def self.m = 1\nend\n") }
    config = Saboteur::Config.new({}, root: @root)

    expect(described_class.new(config, diags).select(files)).to eq([])
    expect(io.string).to include("3 subject(s) skipped: intentionally untested in config/saboteur_custom_map.rb: " \
                                 "M1.m, M2.m, M3.m")
    expect(io.string).not_to include("...")
  end

  # An injected map wins over the one on disk: the engine shares one load
  # with guessing, so selection must not quietly reload (#369 review).
  it "uses the injected custom map instead of loading from disk" do
    FileUtils.mkdir_p(File.join(@root, "config"))
    write("config/saboteur_custom_map.rb", "SABOTEUR_CUSTOM_MAP = {\n  \"cart.rb\" => []\n}.freeze\n")
    config = Saboteur::Config.new({}, root: @root)
    selection = described_class.new(config, diagnostics, custom_map: Saboteur::CustomMap.new([]))
    expect(selection.select([write("cart.rb", source)]).map(&:id)).to eq(["Shop::Cart#total", "Shop::Cart.empty"])
  end

  # At exactly five every id fits: the note lists them all, no ellipsis.
  it "lists every id without an ellipsis at five skipped subjects" do
    FileUtils.mkdir_p(File.join(@root, "config"))
    entries = (1..5).map { |i| "  \"f#{i}.rb\" => []" }.join(",\n")
    write("config/saboteur_custom_map.rb", "SABOTEUR_CUSTOM_MAP = {\n#{entries}\n}.freeze\n")
    io = StringIO.new
    diags = Saboteur::Engine::Diagnostics.new(io)
    files = (1..5).map { |i| write("f#{i}.rb", "module M#{i}\n  def self.m = 1\nend\n") }
    config = Saboteur::Config.new({}, root: @root)

    expect(described_class.new(config, diags).select(files)).to eq([])
    expect(io.string).to include("5 subject(s) skipped: intentionally untested in config/saboteur_custom_map.rb:")
    expect(io.string).not_to include("...")
  end

  # A file the custom map marks intentionally untested ("path" => []) is
  # never mutated: with no test there is no signal, and a guessed selection
  # would read its empty spec list as "run the whole suite" (#369 review).
  it "skips subjects whose file the custom map marks intentionally untested" do
    out = StringIO.new
    diags = Saboteur::Engine::Diagnostics.new(out)
    FileUtils.mkdir_p(File.join(@root, "config"))
    write("config/saboteur_custom_map.rb", "SABOTEUR_CUSTOM_MAP = {\n  \"cart.rb\" => []\n}.freeze\n")
    file = write("cart.rb", source)
    config = Saboteur::Config.new({}, root: @root)
    expect(described_class.new(config, diags).select([file])).to eq([])
    expect(out.string).to include("intentionally untested", "Shop::Cart#total")
  end

  it "keeps subjects whose file the custom map maps to specs" do
    FileUtils.mkdir_p(File.join(@root, "config"))
    FileUtils.mkdir_p(File.join(@root, "spec"))
    write("config/saboteur_custom_map.rb",
          "SABOTEUR_CUSTOM_MAP = {\n  \"cart.rb\" => [\"spec/cart_spec.rb\"]\n}.freeze\n")
    write("spec/cart_spec.rb", "# x\n")
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

  it "says specs are not mutated when every subjectless changed file is a spec file (#371)" do
    # The repro from #371: spec paths misread as source scope reach this
    # warning, where "may not parse" misdiagnoses them.
    FileUtils.mkdir_p(File.join(@root, "spec"))
    spec_file = write("spec/thing_spec.rb", "RSpec.describe(X) { it { expect(1).to eq(1) } }\n")
    [%w[init -q], %w[add .], %w[commit -q -m base]].each do |args|
      Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: @root)
    end
    File.write(spec_file, "RSpec.describe(X) { it { expect(1).to eq(1) } } # more\n")
    config = Saboteur::Config.new({ "since" => "HEAD", "include" => ["**/*.rb"] }, root: @root)
    described_class.new(config, diagnostics).select([spec_file])
    expect(diagnostics.warnings).to include(a_string_matching(/specs are not mutated - pass them with --test/))
  end

  it "keeps the parse/method hint when a spec file mixes with other subjectless files (#371)" do
    FileUtils.mkdir_p(File.join(@root, "spec"))
    spec_file = write("spec/thing_spec.rb", "RSpec.describe(X) { it { expect(1).to eq(1) } }\n")
    note = write("note.rb", "# just a comment\n")
    [%w[init -q], %w[add .], %w[commit -q -m base]].each do |args|
      Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: @root)
    end
    File.write(spec_file, "RSpec.describe(X) { it { expect(1).to eq(1) } } # more\n")
    File.write(note, "# just a comment\n# more\n")
    config = Saboteur::Config.new({ "since" => "HEAD", "include" => ["**/*.rb"] }, root: @root)
    described_class.new(config, diagnostics).select([spec_file, note])
    expect(diagnostics.warnings).to include(a_string_matching(/may not parse/))
    expect(diagnostics.warnings).not_to include(a_string_matching(/specs are not mutated/))
  end

  it "keeps subjects matching --subject patterns, including namespace prefixes" do
    file = write("cart.rb", source)
    expect(select([file], subjects: ["Shop::Cart.empty"]).map(&:id)).to eq(["Shop::Cart.empty"])
    expect(select([file], subjects: ["Shop"]).size).to eq(2)
    expect { select([file], subjects: ["Sho"]) }.to raise_error(Saboteur::ConfigError,
                                                                /--subject Sho matches no subject/)
  end

  # A typo must not pass silently: when EVERY pattern misses, the run is
  # usage-class (exit 2 at the CLI) instead of a green zero-subject
  # summary (#379).
  it "refuses the run when every --subject pattern matches nothing" do
    file = write("cart.rb", source)
    expect { select([file], subjects: ["Shop::Car", "Nope"]) }
      .to raise_error(Saboteur::ConfigError,
                      "--subject Shop::Car, Nope matches no subject (patterns are names like " \
                      "Klass, Klass#meth or Klass.meth, not globs)")
  end

  # Patterns are names, not globs: "Item*" matches nothing. A partial
  # miss keeps the run but names both the missing pattern and the
  # matched count, so a typo is visible in CI logs (#379).
  it "warns about a --subject pattern that matches no subject and reports the matched count" do
    select([write("cart.rb", source)], subjects: ["Shop::Cart", "Cart*"])
    expect(diagnostics.warnings).to eq(["--subject Cart* matches no subject (patterns are names like " \
                                        "Klass, Klass#meth or Klass.meth, not globs)",
                                        "1 of 2 --subject patterns matched"])
  end

  # The count is a subtraction, not a restatement of the miss count: with
  # three patterns and one miss the matched count is two (#379 dogfood).
  it "reports the matched count when only one of three patterns misses" do
    select([write("cart.rb", source)], subjects: ["Shop::Cart", "Shop::Cart.empty", "Nope"])
    expect(diagnostics.warnings).to include("2 of 3 --subject patterns matched")
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
      expect(err.string).to eq("saboteur: 2 changed subject(s) differ only in comments or formatting, " \
                               "so they are skipped: Cart#total, Cart#count\n")
    end

    it "keeps the method whose code changed and skips the other" do
      file = commit_base(two_methods)
      File.write(file, two_methods.sub("1 + 1", "1 + 2").sub("    2\n", "    2 # two\n"))

      expect(select([file], since: "HEAD").map(&:id)).to eq(["Cart#total"])
      expect(err.string).to include("1 changed subject(s) differ only in comments or formatting, so they are " \
                                    "skipped: Cart#count")
    end

    # The layout filter narrows mutants, never subject selection (#313): a
    # re-indented method is still found, then reported as formatting-only.
    it "reports a method that was only re-indented as formatting-only, not as a file without subjects" do
      file = commit_base(two_methods)
      File.write(file, two_methods.sub("    1 + 1\n", "      1 + 1\n"))

      expect(select([file], since: "HEAD")).to be_empty
      expect(err.string).to eq("saboteur: 1 changed subject(s) differ only in comments or formatting, " \
                               "so they are skipped: Cart#total\n")
    end

    # Both maps always come back as a pair, even when the diff changed
    # nothing: callers destructure [changed, behavior] (#549).
    it "returns both line maps when the diff changes nothing" do
      file = commit_base(source)
      selection = Saboteur::Engine::SubjectSelection.new(Saboteur::Config.new({ "since" => "HEAD" }, root: @root),
                                                         diagnostics)
      selection.select([file])
      expect(selection.send(:changed_line_maps)).to eq([{}, {}])
    end

    it "reports a re-indented sibling beside a real edit, and scopes mutants to the real edit" do
      file = commit_base(two_methods)
      File.write(file, two_methods.sub("1 + 1", "1 + 2").sub("    2\n", "      2\n"))
      selection = Saboteur::Engine::SubjectSelection.new(Saboteur::Config.new({ "since" => "HEAD" }, root: @root),
                                                         diagnostics)

      expect(selection.select([file]).map(&:id)).to eq(["Cart#total"])
      expect(err.string).to include("skipped: Cart#count")
      expect(selection.changed_lines.values.first).to eq(Set[3, 7])
      expect(selection.behavior_lines.values.first).to eq(Set[3])
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
      expect(err.string).to include("6 changed subject(s)").and end_with("Cart#m4, Cart#m5, ...\n")
    end

    it "scopes the diff to the selected files and reports through the run diagnostics" do
      file = commit_base(two_methods)
      allow(Saboteur::Selection::GitDiff).to receive(:line_maps).and_call_original
      select([file], since: "HEAD")
      expect(Saboteur::Selection::GitDiff).to have_received(:line_maps)
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
      file = write("cart.rb", "class Cart\n  register :cart\n\n  def total = 1\nend\n")
      commit_all
      File.write(file, "class Cart\n  register :shop\n\n  def total = 1\nend\n")

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
      fresh = write("fresh.rb", "register :none\n")
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
      expect(diagnostics.warnings.size).to eq(2)
      expect(diagnostics.warnings.first).to include("changed constant Note::KIND in note.rb")
      expect(diagnostics.warnings.first).not_to include("cart.rb")
      # The umbrella warning (#232) still stands: nothing was mutated from
      # note.rb. The specific diagnostic above it says why.
      expect(diagnostics.warnings.last).to include("1 changed Ruby file(s) have no subjects", "note.rb")
      expect(diagnostics.warnings.last).not_to include("cart.rb")
    end

    it "names at most five subjectless files, with an ellipsis for the rest" do
      files = (1..6).map { |n| write("f#{n}.rb", "class F#{n}\n  register :a\n\n  def x = 1\nend\n") }
      commit_all
      files.each_with_index do |file, n|
        File.write(file, "class F#{n + 1}\n  register :b\n\n  def x = 1\nend\n")
      end

      expect(select(files, since: "HEAD")).to be_empty
      expect(diagnostics.warnings.size).to eq(1)
      warning = diagnostics.warnings.first
      expect(warning).to include("--since: 6 changed Ruby file(s) have no subjects")
      expect(warning).to include("from them: f1.rb, f2.rb, f3.rb, f4.rb, f5.rb, ...")
      expect(warning).not_to include("f6.rb")
    end

    it "lists five subjectless files in full, without an ellipsis" do
      files = (1..5).map { |n| write("g#{n}.rb", "class G#{n}\n  register :a\n\n  def x = 1\nend\n") }
      commit_all
      files.each_with_index do |file, n|
        File.write(file, "class G#{n + 1}\n  register :b\n\n  def x = 1\nend\n")
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

    it "refuses when a --subject pattern matched no subject, even before the diff narrows (#379)" do
      file = write("cart.rb", source)
      commit_all
      File.write(file, source.sub("def total = 1", "def total = 2"))

      expect { select([file], since: "HEAD", subjects: ["Other"]) }
        .to raise_error(Saboteur::ConfigError, /--subject Other matches no subject/)
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

RSpec.describe Saboteur::Engine::SubjectSelection, "constant literals in --since mode (issue #306)" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  let(:err) { StringIO.new }
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(err) }
  let(:base) do
    "module Shop\n  RULES = {\n    city: \"required\"\n  }.freeze\n\n  def self.rule_for(f) = RULES.fetch(f)\nend\n"
  end

  def select(files, **settings)
    config = Saboteur::Config.new(settings.transform_keys(&:to_s), root: @root)
    described_class.new(config, diagnostics).select(files)
  end

  def commit_base(text, name = "rules.rb")
    file = File.join(@root, name)
    File.write(file, text)
    [%w[init -q], %w[add .], %w[commit -q -m base]].each do |args|
      Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: @root)
    end
    file
  end

  it "selects a constant hash whose entries changed, alongside no method" do
    file = commit_base(base)
    File.write(file, base.sub("city: \"required\"", "city: \"required\",\n    zip: \"optional\""))

    expect(select([file], since: "HEAD").map(&:id)).to eq(["Shop::RULES"])
  end

  it "skips a constant whose only change is a comment, like a method" do
    file = commit_base(base)
    File.write(file, base.sub("city: \"required\"", "city: \"required\" # must"))

    expect(select([file], since: "HEAD")).to be_empty
    expect(err.string).to include("1 changed subject(s) differ only in comments or formatting")
  end

  # Monorepo layout: the project root sits below the git toplevel, so the
  # diff paths carry the subdir prefix. The deletion-only exclusion must
  # still fire - in canonical-absolute space (#484).
  it "selects nothing from a deletion-only file when the project root sits below the git toplevel (#484)" do
    FileUtils.mkdir_p(File.join(@root, "sub"))
    file = commit_base("module Plugin\n  def rules\n    Helper.validate(1)\n    Helper.call(1, 2)\n  end\nend\n",
                       "sub/plugin.rb")
    File.write(file, "module Plugin\n  def rules\n    Helper.call(1, 2)\n  end\nend\n")
    config = Saboteur::Config.new({ "since" => "HEAD" }, root: File.join(@root, "sub"))
    expect(described_class.new(config, diagnostics).select([file])).to be_empty
  end

  it "returns an empty changed map and an empty behavior map when nothing changed since the ref" do
    file = commit_base(base)
    config = Saboteur::Config.new({ "since" => "HEAD" }, root: @root)
    selection = described_class.new(config, diagnostics)
    selection.select([file])
    expect(selection.send(:changed_line_maps)).to eq([{}, {}])
  end

  it "narrows constant subjects to --subject patterns by their Klass::CONST id" do
    file = commit_base(base)
    File.write(file, base.sub("city: \"required\"", "city: \"required\",\n    zip: \"optional\""))

    expect(select([file], since: "HEAD", subjects: ["Shop::RULES"]).map(&:id)).to eq(["Shop::RULES"])
    expect(select([file], since: "HEAD", subjects: ["Shop.rule_for"])).to be_empty
  end

  it "attaches consumer lines across files to the surviving constants" do
    file = commit_base(base)
    consumer = File.join(@root, "cart.rb")
    File.write(consumer, "module Shop\n  class Cart\n    def rules = RULES\n  end\nend\n")
    Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", "add", ".", chdir: @root)
    Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "cart",
                   chdir: @root)
    File.write(file, base.sub("city: \"required\"", "city: \"required\",\n    zip: \"optional\""))

    subject = select([file, consumer], since: "HEAD").first
    expect(subject.consumer_lines).to eq({ file => [7], consumer => [3] })
  end

  it "explains an unsupported changed constant, then the umbrella no-subjects warning (#232, #306)" do
    file = commit_base("module Shop\n  RULES = build_rules\nend\n")
    File.write(file, File.read(file).sub("build_rules", "build_more_rules"))

    expect(select([file], since: "HEAD")).to be_empty
    expect(diagnostics.warnings.size).to eq(2)
    expect(diagnostics.warnings.first).to include("changed constant Shop::RULES", "not a hash or array literal")
    expect(diagnostics.warnings.last).to include("1 changed Ruby file(s) have no subjects", "rules.rb")
  end

  it "does not pick up constants outside --since mode" do
    file = commit_base(base)
    expect(select([file]).map(&:id)).to eq(["Shop.rule_for"])
  end
end

RSpec.describe Saboteur::Engine::SubjectSelection, "constant safety and observability (#319)" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  let(:err) { StringIO.new }
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(err) }

  def select(files, test_files: nil, **settings)
    config = Saboteur::Config.new(settings.transform_keys(&:to_s), root: @root)
    described_class.new(config, diagnostics, test_files: test_files).select(files)
  end

  def commit_base(name, text)
    file = File.join(@root, name)
    File.write(file, text)
    [%w[init -q], %w[add .], %w[commit -q -m base]].each do |args|
      Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: @root)
    end
    file
  end

  it "skips constants in a file that runs denylisted code at load, with a way out" do
    file = commit_base("rules.rb", "FileUtils.rm_rf(\"/tmp/x\")\nRULES = {\n  a: 1\n}.freeze\n")
    File.write(file, File.read(file).sub("a: 1", "a: 1,\n  b: 2"))

    expect(select([file], since: "HEAD")).to be_empty
    expect(diagnostics.warnings.join).to include("FileUtils.rm_rf(\"/tmp/x\")", "c.whole_file",
                                                 "move the literal into its own file")
  end

  # The denylist is not the boundary: a top-level helper call, a
  # registration or a write to disk passes DEFAULT_HAZARD yet still runs
  # again on every replay. Any unvetted load-time code skips the file's
  # constants (#319).
  it "skips constants when the file runs unvetted code at load, denylist or not" do
    file = commit_base("rules.rb", "RULES = {\n  a: 1\n}.freeze\nRegistry.register(RULES)\n")
    File.write(file, File.read(file).sub("a: 1", "a: 1,\n  b: 2"))

    expect(select([file], since: "HEAD")).to be_empty
    expect(diagnostics.warnings.join).to include("Registry.register(RULES)", "c.whole_file")
  end

  it "admits a skipped constant through the whole_file opt-in" do
    file = commit_base("rules.rb", "RULES = {\n  a: 1\n}.freeze\nvalidate!(RULES)\n")
    File.write(file, File.read(file).sub("a: 1", "a: 1,\n  b: 2"))

    expect(select([file], since: "HEAD").map(&:id)).to eq([])
    expect(select([file], since: "HEAD", whole_file: ["RULES"]).map(&:id)).to eq(["RULES"])
  end

  it "replays a file whose load-time code is only requires, defs and literal assignments" do
    file = commit_base("rules.rb",
                       "require \"json\"\nRULES = {\n  a: 1\n}.freeze\ndef rule_for(k) = RULES[k]\n")
    File.write(file, File.read(file).sub("a: 1", "a: 1,\n  b: 2"))

    expect(select([file], since: "HEAD").map(&:id)).to eq(["RULES"])
  end

  it "skips a constant whose only reads capture the value at load time elsewhere" do
    file = commit_base("rules.rb", "RULES = {\n  a: 1\n}.freeze\n")
    copy = File.join(@root, "copy.rb")
    File.write(copy, "COPY = RULES\n")
    Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", "add", ".", chdir: @root)
    Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "c",
                   chdir: @root)
    File.write(file, File.read(file).sub("a: 1", "a: 1,\n  b: 2"))

    expect(select([file, copy], since: "HEAD")).to be_empty
    expect(diagnostics.warnings.join).to include("--since: changed constant RULES in rules.rb is not " \
                                                 "mutated: its only",
                                                 "capture the value at load time",
                                                 "observe a change to it")
  end

  it "treats a boot-time block capture like a plain load capture (#319)" do
    file = commit_base("rules.rb", "RULES = {\n  a: 1\n}.freeze\n")
    copy = File.join(@root, "copy.rb")
    File.write(copy, "1.times { COPY = RULES }\n")
    Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", "add", ".", chdir: @root)
    Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "c",
                   chdir: @root)
    File.write(file, File.read(file).sub("a: 1", "a: 1,\n  b: 2"))

    expect(select([file, copy], since: "HEAD")).to be_empty
    expect(diagnostics.warnings.join).to include("RULES in rules.rb", "capture the value at load time",
                                                 "observe a change to it")
  end

  it "scans the integration's loaded spec files in the --all case, not only the conventional tree" do
    file = commit_base("rules.rb", "RULES = {\n  a: 1\n}.freeze\n")
    suite = File.join(@root, "custom_suite", "rules_spec.rb")
    FileUtils.mkdir_p(File.dirname(suite))
    File.write(suite, "RSpec.describe(\"RULES\") { it(\"reads\") { expect(RULES[:a]).to eq(1) } }\n")
    File.write(file, File.read(file).sub("a: 1", "a: 1,\n  b: 2"))

    # The conventional spec tree holds nothing, so the guess alone never
    # finds the consumer; the configured integration's files do.
    expect(select([file], since: "HEAD").first.consumer_lines).to eq({})
    subject = select([file], since: "HEAD", test_files: [File.realpath(suite)]).first
    expect(subject.consumer_lines[File.realpath(suite)]).to eq([1])
  end

  it "expands directory test paths and the default spec tree for the consumer scan (#319)" do
    file = commit_base("rules.rb", "RULES = {\n  a: 1\n}.freeze\n")
    spec = File.join(@root, "spec", "rules_spec.rb")
    FileUtils.mkdir_p(File.dirname(spec))
    File.write(spec, "RSpec.describe(\"RULES\") { it(\"reads\") { expect(RULES[:a]).to eq(1) } }\n")
    File.write(file, File.read(file).sub("a: 1", "a: 1,\n  b: 2"))

    by_dir = select([file], since: "HEAD", tests: ["spec"]).first
    expect(by_dir.consumer_lines[File.realpath(spec)]).to eq([1])
    by_default = select([file], since: "HEAD").first
    expect(by_default.consumer_lines[File.realpath(spec)]).to eq([1])
  end

  it "counts spec files as consumers: a spec reading the constant covers the mutant" do
    file = commit_base("rules.rb", "RULES = {\n  a: 1\n}.freeze\n")
    spec = File.join(@root, "spec", "rules_spec.rb")
    FileUtils.mkdir_p(File.dirname(spec))
    File.write(spec, <<~RUBY)
      require_relative "../rules"
      RSpec.describe("RULES") { it("reads") { expect(RULES[:a]).to eq(1) } }
    RUBY
    File.write(file, File.read(file).sub("a: 1", "a: 1,\n  b: 2"))

    subject = select([file], since: "HEAD", tests: ["spec/rules_spec.rb"]).first
    expect(subject.consumer_lines[File.realpath(spec)]).to eq([2])
  end

  it "ignores reads shadowed by an inner scope's own constant" do
    file = commit_base("rules.rb", <<~RUBY)
      module Shop
        RULES = {
          a: 1
        }.freeze

        def self.rule_for(f) = RULES.fetch(f)
      end
    RUBY
    consumer = File.join(@root, "inner.rb")
    File.write(consumer, "module Shop\n  class Inner\n    RULES = { b: 2 }.freeze\n\n    def own = RULES\n  end\nend\n")
    Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", "add", ".", chdir: @root)
    Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "c",
                   chdir: @root)
    File.write(file, File.read(file).sub("a: 1", "a: 1,\n    b: 2"))

    subject = select([file, consumer], since: "HEAD").first
    expect(subject.consumer_lines.keys).to eq([file])
  end

  it "files_matching finds a file holding only the named constant" do
    file = File.join(@root, "rules.rb")
    File.write(file, "RULES = { a: 1 }.freeze\n")
    found = described_class.files_matching(@root, [file], ["RULES"], { "since" => "HEAD" })
    expect(found).to eq(["rules.rb"])
    expect(described_class.files_matching(@root, [file], ["RULES"])).to be_empty
  end
end

RSpec.describe Saboteur::Engine::SubjectSelection, "constant selection edges (#319 dogfood)" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  let(:err) { StringIO.new }
  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(err) }

  def select(files, **settings)
    config = Saboteur::Config.new(settings.transform_keys(&:to_s), root: @root)
    described_class.new(config, diagnostics).select(files)
  end

  def commit_base(name, text)
    file = File.join(@root, name)
    File.write(file, text)
    [%w[init -q], %w[add .], %w[commit -q -m base]].each do |args|
      Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: @root)
    end
    file
  end

  def commit_all
    Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", "add", ".", chdir: @root)
    Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "more",
                   chdir: @root)
  end

  def change_rules(file)
    File.write(file, File.read(file).sub("a: 1", "a: 1,\n  b: 2"))
  end

  it "files_matching matches when one constant of several matches one pattern of several" do
    file = File.join(@root, "rules.rb")
    File.write(file, "RULES = { a: 1 }.freeze\nOTHER = { b: 2 }.freeze\n")
    found = described_class.files_matching(@root, [file], %w[Nope RULES], { "since" => "HEAD" })
    expect(found).to eq(["rules.rb"])
  end

  it "files_matching skips a file whose constants all miss the patterns" do
    file = File.join(@root, "rules.rb")
    File.write(file, "RULES = { a: 1 }.freeze\nOTHER = { b: 2 }.freeze\n")
    found = described_class.files_matching(@root, [file], %w[Nope Nah], { "since" => "HEAD" })
    expect(found).to be_empty
  end

  it "ignores a changed non-Ruby file even when its text parses as a constant" do
    commit_base("rules.rb", "RULES = {\n  a: 1\n}.freeze\n")
    notes = File.join(@root, "notes.md")
    File.write(notes, "RULES = { a: 1 }.freeze\n")

    expect(select([notes], since: "HEAD")).to be_empty
  end

  it "does not warn about an unsupported constant the diff did not touch" do
    file = commit_base("rules.rb", "RULES = {\n  a: 1\n}.freeze\nOTHER = build_other\n")
    change_rules(file)

    select([file], since: "HEAD")
    expect(diagnostics.warnings.grep(/changed constant/)).to be_empty
  end

  it "admits opted-in constants without the load-code warning" do
    file = commit_base("rules.rb", "RULES = {\n  a: 1\n}.freeze\nvalidate!(RULES)\n")
    change_rules(file)

    expect(select([file], since: "HEAD", whole_file: ["RULES"]).map(&:id)).to eq(["RULES"])
    expect(diagnostics.warnings.grep(/not mutated/)).to be_empty
  end

  it "applies the configured hazard list to load-time vetting" do
    file = commit_base("rules.rb", "require \"json\"\nRULES = {\n  a: 1\n}.freeze\n")
    change_rules(file)

    expect(select([file], since: "HEAD", hazard: ["require"]).map(&:id)).to eq([])
    expect(diagnostics.warnings.join).to include("require")
  end

  it "names the first two load-time reasons, joined, in the skip warning" do
    file = commit_base("rules.rb",
                       "FileUtils.rm_rf(\"/tmp/x\")\nFileUtils.mkdir_p(\"/tmp/y\")\nsystem(\"ls\")\n" \
                       "RULES = {\n  a: 1\n}.freeze\n")
    change_rules(file)

    expect(select([file], since: "HEAD")).to be_empty
    # Hazard-denylist entries surface ahead of merely unvetted code, and
    # the warning lists at most two reasons; the third stays unnamed.
    expect(diagnostics.warnings.join).to include("system(\"ls\"), FileUtils.rm_rf(\"/tmp/x\")",
                                                 "in rules.rb are not mutated",
                                                 "at load (",
                                                 "that every constant mutant would run again",
                                                 "cannot vet what re-running it does",
                                                 "c.whole_file to replay the file anyway",
                                                 "move the literal into its own file")
    expect(diagnostics.warnings.join).not_to include("mkdir_p")
  end

  it "names the file of an unsupported changed constant in the warning" do
    file = commit_base("rules.rb", "RULES = build_rules\n")
    File.write(file, "RULES = build_more_rules\n")

    expect(select([file], since: "HEAD")).to be_empty
    expect(diagnostics.warnings.first).to include("changed constant RULES in rules.rb is not mutated",
                                                  ". Only hash and array literal entries are mutated")
  end

  it "keeps a constant read at runtime even when another file captures it at load" do
    file = commit_base("rules.rb", "RULES = {\n  a: 1\n}.freeze\n")
    runtime = File.join(@root, "user.rb")
    File.write(runtime, "def current = RULES\n")
    copy = File.join(@root, "copy.rb")
    File.write(copy, "COPY = RULES\n")
    commit_all
    change_rules(file)

    subject = select([file, runtime, copy], since: "HEAD").first
    expect(subject).not_to be_nil
    expect(subject.consumer_lines).to eq(runtime => [1])
    expect(subject.consumer_defs).to eq(runtime => [1], copy => [])
  end

  it "keeps a constant observed by a load read in its own file" do
    file = commit_base("rules.rb", "RULES = {\n  a: 1\n}.freeze\nCOPY = RULES\n")
    change_rules(file)

    subject = select([file], since: "HEAD", whole_file: ["RULES"]).first
    expect(subject).not_to be_nil
    expect(subject.consumer_lines).to eq(file => [5])
  end

  it "uses only the configured tests, not the default spec tree" do
    file = commit_base("rules.rb", "RULES = {\n  a: 1\n}.freeze\n")
    default_spec = File.join(@root, "spec", "rules_spec.rb")
    other_spec = File.join(@root, "other", "rules_spec.rb")
    [default_spec, other_spec].each do |spec|
      FileUtils.mkdir_p(File.dirname(spec))
      File.write(spec, "RSpec.describe(\"x\") { it { RULES } }\n")
    end
    change_rules(file)

    subject = select([file], since: "HEAD", tests: ["other"]).first
    expect(subject.consumer_lines.keys).to eq([File.realpath(other_spec)])
  end

  it "expands the default spec tree recursively and no other directory" do
    file = commit_base("rules.rb", "RULES = {\n  a: 1\n}.freeze\n")
    deep_spec = File.join(@root, "spec", "deep", "rules_spec.rb")
    stray_spec = File.join(@root, "other", "rules_spec.rb")
    [deep_spec, stray_spec].each do |spec|
      FileUtils.mkdir_p(File.dirname(spec))
      File.write(spec, "RSpec.describe(\"x\") { it { RULES } }\n")
    end
    change_rules(file)

    subject = select([file], since: "HEAD").first
    expect(subject.consumer_lines.keys).to eq([File.realpath(deep_spec)])
  end

  it "ignores test entries that are not existing Ruby files" do
    file = commit_base("rules.rb", "RULES = {\n  a: 1\n}.freeze\n")
    notes = File.join(@root, "notes.txt")
    File.write(notes, "RULES\n")
    change_rules(file)

    subject = select([file], since: "HEAD", tests: ["notes.txt", "missing.rb"]).first
    expect(subject).not_to be_nil
    expect(subject.consumer_lines).to eq({})
    expect(diagnostics.warnings.grep(/load time/)).to be_empty
  end
end
