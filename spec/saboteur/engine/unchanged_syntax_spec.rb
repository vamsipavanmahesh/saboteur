# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require "tmpdir"

RSpec.describe Saboteur::Engine::UnchangedSyntax do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  let(:before) { "class Cart\n  def total(a)\n    x = a + 1\n    x\n  end\nend\n" }
  let(:file) { File.join(@root, "cart.rb") }

  def git(*args)
    Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: @root)
  end

  # Commits `before`, rewrites the file to `after`, and asks about the method.
  def unchanged?(after, base_text: before, id: "Cart#total")
    File.write(file, base_text)
    git("init", "-q")
    git("add", ".")
    git("commit", "-q", "-m", "base")
    File.write(file, after)
    subject = Saboteur::SubjectFinder.new.call(file).subjects.find { |candidate| candidate.id == id }
    described_class.new(git("rev-parse", "HEAD").first.strip, root: @root).unchanged?(subject)
  end

  describe "#deleted_subjects (#466)" do
    def deleted_subjects(files, base_text: before, after: nil)
      File.write(file, base_text)
      git("init", "-q")
      git("add", ".")
      git("commit", "-q", "-m", "base")
      File.write(file, after) if after
      described_class.new(git("rev-parse", "HEAD").first.strip, root: @root).deleted_subjects(files)
    end

    it "finds a method removed from the working tree" do
      expect(deleted_subjects([file], after: "class Cart\nend\n").map(&:id)).to eq(["Cart#total"])
    end

    it "does not report a method that moved but still exists" do
      after = "class Cart\n  def other = 2\n\n  def total(a)\n    x = a + 1\n    x\n  end\nend\n"
      moved = before.sub("end\nend\n", "end\n\n  def other = 2\nend\n")
      expect(deleted_subjects([file], base_text: moved, after: after)).to be_empty
    end

    it "ignores a non-Ruby file even when its base text defined a method" do
      gemfile = File.join(@root, "Gemfile")
      File.write(gemfile, "class C\n  def total = 1\nend\n")
      git("init", "-q")
      git("add", ".")
      git("commit", "-q", "-m", "base")
      File.write(gemfile, "# none left\n")
      comparison = described_class.new(git("rev-parse", "HEAD").first.strip, root: @root)
      expect(comparison.deleted_subjects([gemfile])).to be_empty
    end

    it "skips a changed file nested too deeply instead of refusing the run (#719, #730)" do
      # The diff reaches files outside the mutation scope (fixtures,
      # scripts): they are probed here without ever passing the in-scope
      # depth guard, so a too-deep one must not fail the run.
      deep = File.join(@root, "deep.rb")
      File.write(deep, "#{'a(' * 1500}1#{')' * 1500}\n")
      git("init", "-q")
      git("add", ".")
      git("commit", "-q", "-m", "base")
      comparison = described_class.new(git("rev-parse", "HEAD").first.strip, root: @root)
      expect { comparison.deleted_subjects([deep]) }.not_to raise_error
      expect(comparison.deleted_subjects([deep])).to eq([])
    end

    it "ignores a path that no longer exists on disk" do
      File.write(file, before)
      git("init", "-q")
      git("add", ".")
      git("commit", "-q", "-m", "base")
      File.delete(file)
      comparison = described_class.new(git("rev-parse", "HEAD").first.strip, root: @root)
      expect(comparison.deleted_subjects([file])).to be_empty
    end
  end

  it "is true for a comment, a blank line and spacing" do
    after = "class Cart\n  # explains total\n  def total(a)\n    x = a+1 # inline\n\n    x\n  end\nend\n"

    expect(unchanged?(after)).to be(true)
  end

  it "is true when two statements move onto one line" do
    expect(unchanged?(before.sub("x = a + 1\n    x", "x = a + 1; x"))).to be(true)
  end

  it "retains directive addition, removal, operator and reason changes" do
    directive = ' # saboteur:disable-line arithmetic reason="checked elsewhere"'
    suppressed = before.sub("a + 1", "a + 1#{directive}")
    expect(unchanged?(suppressed)).to be(false)
    expect(unchanged?(before, base_text: suppressed)).to be(false)
    expect(unchanged?(suppressed.sub("arithmetic", "literal_number"), base_text: suppressed)).to be(false)
    expect(unchanged?(suppressed.sub("checked elsewhere", "other evidence"), base_text: suppressed)).to be(false)
  end

  it "skips formatting around an unchanged directive, but retains a directive moved to other code" do
    suppressed = before.sub("a + 1", 'a + 1 # saboteur:disable-line arithmetic reason="why"')
    expect(unchanged?(suppressed.sub("a + 1", "a+1"), base_text: suppressed)).to be(true)
    moved = suppressed.sub(' # saboteur:disable-line arithmetic reason="why"', "")
                      .sub("    x\n", "    x # saboteur:disable-line arithmetic reason=\"why\"\n")
    expect(unchanged?(moved, base_text: suppressed)).to be(false)
  end

  it "is false when a value changes" do
    expect(unchanged?(before.sub("a + 1", "a + 2"))).to be(false)
  end

  it "is false when an operator changes" do
    expect(unchanged?(before.sub("a + 1", "a - 1"))).to be(false)
  end

  it "is false when a boolean operator changes between && and ||" do
    base = "class Cart\n  def total(a)\n    a && 1\n  end\nend\n"
    expect(unchanged?(base.sub("&&", "||"), base_text: base)).to be(false)
  end

  it "is false when the line a __LINE__ stands for moves" do
    base = "class Cart\n  def total(a)\n    a\n    __LINE__\n  end\nend\n"
    expect(unchanged?(base.sub("    a\n", "    a\n\n"), base_text: base)).to be(false)
    expect(unchanged?(base, base_text: base)).to be(true)
  end

  it "is false when two statements are joined into one call" do
    expect(unchanged?(before.sub("x = a + 1\n    x", "x(a + 1)"))).to be(false)
  end

  it "is false when a string literal changes inside the text" do
    base = "class Cart\n  def total(_a)\n    \"a  b\"\n  end\nend\n"

    expect(unchanged?(base.sub("a  b", "a b"), base_text: base)).to be(false)
  end

  it "is false when the frozen_string_literal comment changes, because string mutability does" do
    expect(unchanged?("# frozen_string_literal: true\n#{before}")).to be(false)
  end

  describe "__LINE__, whose value is where it sits" do
    def method_text(body, above: "")
      "class Cart\n#{above}  def total(a)\n#{body}  end\nend\n"
    end

    {
      "directly" => "    __LINE__\n",
      "inside a call" => "    [a, __LINE__].max\n",
      "inside an interpolation" => "    \"line \#{__LINE__}\"\n",
      "inside a nested block" => "    [a].map { |x| x + __LINE__ }\n",
      "in a heredoc interpolation" => "    <<~TEXT\n      \#{__LINE__}\n    TEXT\n"
    }.each do |where, body|
      it "is false when the method moves down a line, used #{where}" do
        expect(unchanged?(method_text(body, above: "  # note\n"), base_text: method_text(body))).to be(false)
      end

      it "is false when a line is added above it inside the method, used #{where}" do
        edited = method_text(body).sub("    ", "    # note\n    ")

        expect(unchanged?(edited, base_text: method_text(body))).to be(false)
      end

      it "is true when only a comment after it changes, used #{where}" do
        edited = method_text(body).sub("  end\nend", "    # tail\n  end\nend")

        expect(unchanged?(edited, base_text: method_text(body))).to be(true)
      end
    end

    it "is true when only an inline comment changes" do
      expect(unchanged?(method_text("    __LINE__ # now\n"), base_text: method_text("    __LINE__\n"))).to be(true)
    end
  end

  it "is false when the sig in front of the def changes" do
    base = "class Cart\n  sig { returns(Integer) }\n  def total = 1\nend\n"

    expect(unchanged?(base.sub("Integer", "String"), base_text: base)).to be(false)
  end

  it "is false for a method the base did not have" do
    after = "#{before.chomp.chomp('end')}  def other = 1\nend\n"

    expect(unchanged?(after, id: "Cart#other")).to be(false)
  end

  it "is true when code above the method changes, which shifts every node id" do
    above = "class Cart\n  def first_one(a)\n    a * 3\n  end\n\n"

    expect(unchanged?(before.sub("class Cart\n", above))).to be(true)
  end

  it "compares with the base commit, not with what is staged" do
    File.write(file, before)
    git("init", "-q")
    git("add", ".")
    git("commit", "-q", "-m", "base")
    File.write(file, before.sub("a + 1", "a + 2"))
    git("add", ".")
    File.write(file, before.sub("a + 1", "a + 2 # same code as staged"))
    subject = Saboteur::SubjectFinder.new.call(file).subjects.first

    expect(described_class.new(git("rev-parse", "HEAD").first.strip, root: @root).unchanged?(subject)).to be(false)
  end

  it "is false when the base had the name once and the file now defines it twice" do
    twice = "class Cart\n  def total = 1\n  def total = 2\nend\n"

    expect(unchanged?(twice, base_text: "class Cart\n  def total = 1\nend\n")).to be(false)
  end

  it "is false for a method renamed in place" do
    expect(unchanged?(before.sub("def total", "def sum"), id: "Cart#sum")).to be(false)
  end

  it "is false for a file that is new at the base" do
    File.write(File.join(@root, "readme.txt"), "x\n")
    git("init", "-q")
    git("add", ".")
    git("commit", "-q", "-m", "base")
    File.write(file, before)
    subject = Saboteur::SubjectFinder.new.call(file).subjects.first

    expect(described_class.new(git("rev-parse", "HEAD").first.strip, root: @root).unchanged?(subject)).to be(false)
  end

  it "is false when the name is defined twice, because the two cannot be told apart" do
    twice = "class Cart\n  def total = 1\n  def total = 2\nend\n"

    expect(unchanged?(twice, base_text: twice, id: "Cart#total")).to be(false)
  end

  it "is false when the base does not parse" do
    expect(unchanged?(before, base_text: "class Cart\n  def (\nend\n")).to be(false)
  end

  describe ".digest" do
    it "ignores locations and keeps content" do
      one = Prism.parse("a  +  1").value
      two = Prism.parse("a + 1").value

      expect(described_class.digest(one)).to eq(described_class.digest(two))
      expect(described_class.digest(one)).not_to eq(described_class.digest(Prism.parse("a + 2").value))
    end
  end
end
