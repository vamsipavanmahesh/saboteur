# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

require_relative "../../script/ignore_audit/audit"

REPO_ROOT = File.expand_path("../..", __dir__)

RSpec.describe IgnoreAudit::Audit do
  def entry(subject, digest, reason: "equivalent: test")
    Saboteur::IgnoreList::Entry.new(subject: subject, mutation: digest, reason: reason)
  end

  def fake_git(changed:, at: {}, config_changed: false)
    git = instance_double(IgnoreAudit::Git)
    allow(git).to receive(:changed?) do |_base, _head, path = IgnoreAudit::IGNORE_FILE|
      path == IgnoreAudit::CONFIG_FILE ? config_changed : changed
    end
    allow(git).to receive(:entries_at) { |ref| at.fetch(ref, []) }
    git
  end

  let(:out) { StringIO.new }
  let(:resolver) { instance_double(IgnoreAudit::Resolver) }
  let(:kill_proof) { instance_double(IgnoreAudit::KillProof) }

  def run(git:, resolver: self.resolver, kill_proof: self.kill_proof)
    described_class.new(base: "base", head: "head", git: git, out: out,
                        resolver: resolver, kill_proof: kill_proof).call
  end

  it "passes instantly when the ignore file is untouched, never resolving" do
    expect(run(git: fake_git(changed: false))).to eq(0)
    expect(out.string).to include("nothing to audit")
  end

  it "accepts an added digest that arises live" do
    added = entry("Foo#bar", "a" * 16)
    allow(resolver).to receive(:live?).with(added).and_return(true)
    expect(run(git: fake_git(changed: true, at: { "head" => [added] }))).to eq(0)
    expect(out.string).to include("1 added, 0 dropped")
  end

  it "fails an added digest no mutant produces, naming subject and digest" do
    added = entry("Foo#bar", "b" * 16)
    allow(resolver).to receive(:live?).with(added).and_return(false)
    expect(run(git: fake_git(changed: true, at: { "head" => [added] }))).to eq(1)
    expect(out.string).to include("added digest is not live", "Foo#bar", "b" * 16)
  end

  it "accepts a dropped digest that is dead without running the suite" do
    dropped = entry("Foo#bar", "c" * 16)
    allow(resolver).to receive(:live?).with(dropped).and_return(false)
    allow(kill_proof).to receive(:killed?)
    expect(run(git: fake_git(changed: true, at: { "base" => [dropped] }))).to eq(0)
    expect(kill_proof).not_to have_received(:killed?)
  end

  it "accepts a dropped digest that is live only when the suite kills it" do
    dropped = entry("Foo#bar", "d" * 16)
    allow(resolver).to receive(:live?).with(dropped).and_return(true)
    allow(kill_proof).to receive(:killed?).with(dropped).and_return(true)
    expect(run(git: fake_git(changed: true, at: { "base" => [dropped] }))).to eq(0)
  end

  it "fails a dropped digest that is still live and still survives (#571)" do
    dropped = entry("Foo#bar", "e" * 16)
    allow(resolver).to receive(:live?).with(dropped).and_return(true)
    allow(kill_proof).to receive(:killed?).with(dropped).and_return(false)
    expect(run(git: fake_git(changed: true, at: { "base" => [dropped] }))).to eq(1)
    expect(out.string).to include("dropped digest is still live", "Foo#bar", "e" * 16)
  end

  it "treats a reason-only edit as no churn" do
    base_entries = [entry("Foo#bar", "f" * 16, reason: "equivalent: old")]
    head_entries = [entry("Foo#bar", "f" * 16, reason: "equivalent: better")]
    expect(run(git: fake_git(changed: true, at: { "base" => base_entries, "head" => head_entries }))).to eq(0)
    expect(out.string).to include("0 added, 0 dropped")
  end

  it "counts one digest moved to a different subject as churn, not a wash" do
    original = entry("Foo#bar", "g" * 16)
    moved = entry("Baz#qux", "g" * 16)
    allow(resolver).to receive(:live?).with(moved).and_return(true)
    allow(resolver).to receive(:live?).with(original).and_return(false)
    expect(run(git: fake_git(changed: true, at: { "base" => [original], "head" => [moved] }))).to eq(0)
    expect(out.string).to include("1 added, 1 dropped")
  end

  it "is incomplete, never clean, when an ignore file is not static literals" do
    git = fake_git(changed: true)
    allow(git).to receive(:entries_at).with("head").and_raise(IgnoreAudit::Incomplete, "not literals")
    expect(run(git: git)).to eq(3)
    expect(out.string).to include("incomplete", "not literals")
  end

  it "is incomplete when config/saboteur.rb changed in the range, never resolving" do
    expect(resolver).not_to receive(:live?)
    expect(run(git: fake_git(changed: true, config_changed: true))).to eq(3)
    expect(out.string).to include("config/saboteur.rb changed", "incomplete")
  end

  # The security-review bypass: Config::DEFAULTS excludes lib/**/test_*.rb,
  # so a defaults-based resolver never sees TestCommandShape and the live
  # digest f2ba2275de6bc416 reads as dead - dropping it exited 0. The pin
  # digest must be regenerated when test_command_shape.rb changes.
  it "flags dropping the live TestCommandShape digest a defaults-based resolver hides" do
    dropped = entry("Saboteur::Execution::TestCommandShape#ruby_multi_file_simple_command?",
                    "f2ba2275de6bc416")
    real = IgnoreAudit::Resolver.new(root: REPO_ROOT)
    expect(real.live?(dropped)).to be(true)
    allow(kill_proof).to receive(:killed?).with(dropped).and_return(false)
    expect(run(git: fake_git(changed: true, at: { "base" => [dropped] }),
               resolver: real)).to eq(1)
    expect(out.string).to include("dropped digest is still live", "f2ba2275de6bc416")
  end
end

RSpec.describe IgnoreAudit::Resolver do
  def digests_for(root, file, subject_id)
    config = Saboteur::Config.load(root: root)
    candidates = Saboteur::Engine::Candidates.build(
      config, Saboteur::Engine::Diagnostics.new(StringIO.new),
      hazard_guard: Saboteur::MutationSource::HazardGuard.new(config["hazard"])
    )
    subject = Saboteur::SubjectFinder.new.call(file).subjects.find { |item| item.id == subject_id }
    candidates.for(subject).map do |mutation, _|
      mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
    end
  end

  def live_entry(root, file, subject_id, index: 0)
    Saboteur::IgnoreList::Entry.new(subject: subject_id,
                                    mutation: digests_for(root, file, subject_id)[index], reason: "x")
  end

  it "resolves exactly the digests the tree's mutants produce" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      file = File.join(dir, "lib", "widget.rb")
      File.write(file, "class Widget\n  def big?(x)\n    x > 3\n  end\nend\n")
      resolver = described_class.new(root: dir)

      live = live_entry(dir, file, "Widget#big?")
      dead = Saboteur::IgnoreList::Entry.new(subject: "Widget#big?", mutation: "0" * 16, reason: "x")
      unknown = Saboteur::IgnoreList::Entry.new(subject: "Widget#missing", mutation: live.mutation, reason: "x")
      expect(resolver.live?(live)).to be(true)
      expect(resolver.live?(dead)).to be(false)
      expect(resolver.live?(unknown)).to be(false)
    end
  end

  # Config::DEFAULTS excludes lib/**/test_*.rb; the project's own config
  # does not. The resolver must follow the project config, not DEFAULTS.
  it "resolves subjects under default-excluded names the project config includes" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      FileUtils.mkdir_p(File.join(dir, "config"))
      file = File.join(dir, "lib", "test_widget.rb")
      File.write(file, "class TestWidget\n  def big?(x)\n    x > 3\n  end\nend\n")
      File.write(File.join(dir, "config", "saboteur.rb"), <<~RUBY)
        Saboteur.configure do |c|
          c.include = ["lib/**/*.rb"]
          c.exclude = []
        end
      RUBY
      default_excluded = Saboteur::Config::DEFAULTS["exclude"].flat_map { |pattern| Dir[File.join(dir, pattern)] }
      expect(default_excluded).to include(file)
      expect(described_class.new(root: dir).live?(live_entry(dir, file, "TestWidget#big?"))).to be(true)
    end
  end
end

RSpec.describe IgnoreAudit::KillProof do
  def entry(subject, digest)
    Saboteur::IgnoreList::Entry.new(subject: subject, mutation: digest, reason: "x")
  end

  it "replays with the exact run argv: bundle exec exe/saboteur run --id D --subject S --test SPEC" do
    proof = described_class.new(root: "/tmp/audited", spec: "spec/saboteur")
    allow(proof).to receive(:system)
      .with("bundle", "exec", "exe/saboteur", "run", "--id", "d" * 16,
            "--subject", "Foo#bar", "--test", "spec/saboteur", chdir: "/tmp/audited")
      .and_return(true)
    expect(proof.killed?(entry("Foo#bar", "d" * 16))).to be(true)
    expect(proof).to have_received(:system)
  end

  it "takes the spec target from the project config, defaulting to spec" do
    expect(described_class.new(root: REPO_ROOT).send(:spec)).to eq("spec/saboteur")
    Dir.mktmpdir do |dir|
      expect(described_class.new(root: dir).send(:spec)).to eq("spec")
    end
  end

  # The real KillProof, nothing doubled, against the branches fixture: the
  # condition_true mutant of BranchChoice#both dies on the false-case spec.
  # The pin digest must be regenerated when the fixture changes.
  it "replays a killed mutant through the real CLI and reports it killed" do
    root = File.join(REPO_ROOT, "spec/fixtures/projects/branches")
    proof = described_class.new(root: root, exe: File.join(REPO_ROOT, "exe/saboteur"))
    saved = ENV.fetch("BUNDLE_GEMFILE", nil)
    ENV["BUNDLE_GEMFILE"] = File.join(REPO_ROOT, "Gemfile")
    begin
      expect(proof.killed?(entry("BranchChoice#both", "321335f15c4a9f21"))).to be(true)
    ensure
      saved ? ENV["BUNDLE_GEMFILE"] = saved : ENV.delete("BUNDLE_GEMFILE")
      FileUtils.rm_rf(File.join(root, ".saboteur"))
    end
  end
end

RSpec.describe IgnoreAudit::Git do
  def git!(dir, *args)
    out, status = Open3.capture2("git", "-C", dir, *args)
    raise out unless status.success?

    out
  end

  it "reports churn and reads entries at a ref, empty where the file is absent" do
    Dir.mktmpdir do |dir|
      git!(dir, "init", "-q")
      git!(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "root")
      first = git!(dir, "rev-parse", "HEAD").strip
      expect(described_class.new(dir: dir).changed?(first, "HEAD")).to be(false)
      expect(described_class.new(dir: dir).entries_at("HEAD")).to eq([])

      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "saboteur_ignore.rb"), <<~RUBY)
        Saboteur.ignore do |i|
          i.mutation "#{'a' * 16}", subject: "Foo#bar", reason: "equivalent: test"
        end
      RUBY
      git!(dir, "add", ".")
      git!(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "ignore")

      expect(described_class.new(dir: dir).changed?(first, "HEAD")).to be(true)
      entries = described_class.new(dir: dir).entries_at("HEAD")
      expect(entries.map { |entry| [entry.subject, entry.mutation] }).to eq([["Foo#bar", "a" * 16]])
    end
  end
end

RSpec.describe IgnoreAudit::StaticEntries do
  it "reads literal entries, joining adjacent-string reasons and defaulting state" do
    entries = described_class.parse(<<~RUBY)
      # frozen_string_literal: true
      Saboteur.ignore do |i|
        i.mutation "aaaaaaaabbbbbbbb",
                   subject: "Foo#bar",
                   reason: "equivalent: first " \
                           "second"
        i.mutation "ccccccccdddddddd", subject: "Baz#qux", reason: "wont fix", state: "wont_fix"
      end
    RUBY
    expect(entries.map { |entry| [entry.subject, entry.mutation, entry.reason, entry.state] }).to eq(
      [["Foo#bar", "aaaaaaaabbbbbbbb", "equivalent: first second", "accepted_equivalent"],
       ["Baz#qux", "ccccccccdddddddd", "wont fix", "wont_fix"]]
    )
  end

  # The security-review repro: under IgnoreList.load (Kernel.load) this
  # file's `exit 0` ran inside the audit and every churn read clean.
  it "refuses a file that would execute code under Kernel.load (the exit 0 repro)" do
    source = <<~RUBY
      # frozen_string_literal: true
      exit 0
      Saboteur.ignore do |i|
        i.mutation "aaaaaaaaaaaaaaaa", subject: "Foo#bar", reason: "r"
      end
    RUBY
    expect { described_class.parse(source) }.to raise_error(IgnoreAudit::Incomplete, /only Saboteur.ignore blocks/)
  end

  it "refuses interpolation in any entry value" do
    source = <<-'RUBY'
      Saboteur.ignore do |i|
        i.mutation "#{('a' * 16)}", subject: "Foo#bar", reason: "r"
      end
    RUBY
    expect { described_class.parse(source) }.to raise_error(IgnoreAudit::Incomplete)
  end

  it "refuses calls beyond i.mutation inside the block" do
    source = <<~RUBY
      Saboteur.ignore do |i|
        i.mutation "aaaaaaaaaaaaaaaa", subject: "Foo#bar", reason: "r"
        Kernel.system("echo hi")
      end
    RUBY
    expect { described_class.parse(source) }.to raise_error(IgnoreAudit::Incomplete, /more than i.mutation/)
  end

  it "refuses an entry without a reason and a mutation on another receiver" do
    expect { described_class.parse('Saboteur.ignore { |i| i.mutation "aaaaaaaaaaaaaaaa", subject: "Foo#bar" }') }
      .to raise_error(IgnoreAudit::Incomplete, /missing reason/)
    expect { described_class.parse('Saboteur.ignore { |i| j.mutation "aaaaaaaaaaaaaaaa", subject: "F", reason: "r" }') }
      .to raise_error(IgnoreAudit::Incomplete, /more than i.mutation/)
  end

  it "refuses a double-splatted keywords hash instead of crashing (#703 v3 review)" do
    source = <<~RUBY
      Saboteur.ignore do |i|
        i.mutation "aaaaaaaaaaaaaaaa", **{subject: "Foo#bar", reason: "r"}
      end
    RUBY
    expect { described_class.parse(source) }.to raise_error(IgnoreAudit::Incomplete, /literal keywords/)
  end

  # The audit must always read the repo's own file: if a future edit makes
  # it non-literal, every churn run would go incomplete (exit 3).
  it "parses the repo's own config/saboteur_ignore.rb" do
    entries = described_class.parse(File.read(File.join(REPO_ROOT, "config/saboteur_ignore.rb")))
    expect(entries.size).to be > 5
    expect(entries.map(&:mutation)).to all(match(/\A[0-9a-f]{16}\z/))
    expect(entries.map(&:reason)).to all(match(/\S/))
  end
end
