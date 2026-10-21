# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"

require_relative "../../script/ignore_audit/audit"

RSpec.describe IgnoreAudit::Audit, "output and wiring" do
  let(:out) { StringIO.new }
  let(:resolver) { instance_double(IgnoreAudit::Resolver) }
  let(:kill_proof) { instance_double(IgnoreAudit::KillProof) }
  let(:git) { instance_double(IgnoreAudit::Git) }

  def entry(subject, digest)
    Saboteur::IgnoreList::Entry.new(subject: subject, mutation: digest, reason: "equivalent: test")
  end

  def audit(**extra)
    described_class.new(base: "b1", head: "h2", git: git, out: out, **extra)
  end

  it "asks git about the ignore file from base to head and says so when it is unchanged" do
    allow(git).to receive(:changed?).with("b1", "h2").and_return(false)
    expect(audit.call).to eq(0)
    expect(out.string).to eq("ignore-audit: config/saboteur_ignore.rb unchanged in b1..h2; nothing to audit\n")
    expect(git).not_to have_received(:changed?).with("b1", "h2", anything)
  end

  it "stops with 3 and says the config changed before reading any entries" do
    allow(git).to receive(:changed?).with("b1", "h2").and_return(true)
    allow(git).to receive(:changed?).with("b1", "h2", IgnoreAudit::CONFIG_FILE).and_return(true)
    allow(git).to receive(:entries_at)
    expect(audit.call).to eq(3)
    expect(out.string).to eq("ignore-audit: config/saboteur.rb changed in b1..h2; audit is incomplete\n")
    expect(git).not_to have_received(:entries_at)
  end

  it "reports the counts and one exact line per violation" do
    added = entry("Foo#bar", "a" * 16)
    allow(git).to receive(:changed?).and_return(true, false)
    allow(git).to receive(:entries_at) { |ref| ref == "h2" ? [added] : [] }
    allow(resolver).to receive(:live?).and_return(false)
    expect(audit(resolver: resolver, kill_proof: kill_proof).call).to eq(1)
    expect(out.string).to eq(
      "ignore-audit: 1 added, 0 dropped in config/saboteur_ignore.rb\n" \
      "VIOLATION added digest is not live: Foo#bar #{'a' * 16}\n"
    )
  end

  it "builds a real kill proof when none is injected" do
    dropped = entry("Foo#bar", "c" * 16)
    proof = instance_double(IgnoreAudit::KillProof, killed?: true)
    allow(IgnoreAudit::KillProof).to receive(:new).and_return(proof)
    allow(git).to receive(:changed?).and_return(true, false)
    allow(git).to receive(:entries_at) { |ref| ref == "b1" ? [dropped] : [] }
    allow(resolver).to receive(:live?).and_return(true)
    expect(audit(resolver: resolver).call).to eq(0)
    expect(proof).to have_received(:killed?).with(dropped)
  end

  it "builds its resolver on the working directory when none is injected" do
    added = entry("Foo#bar", "a" * 16)
    built = instance_double(IgnoreAudit::Resolver, live?: true)
    allow(IgnoreAudit::Resolver).to receive(:new).and_return(built)
    allow(git).to receive(:changed?).and_return(true, false)
    allow(git).to receive(:entries_at) { |ref| ref == "h2" ? [added] : [] }
    expect(audit(kill_proof: kill_proof).call).to eq(0)
    expect(IgnoreAudit::Resolver).to have_received(:new).with(root: Dir.pwd)
  end
end

RSpec.describe IgnoreAudit::StaticEntries, "refusals" do
  def refusal(source)
    described_class.parse(source)
    raise "expected Incomplete"
  rescue IgnoreAudit::Incomplete => e
    e.message
  end

  let(:entry_line) { 'i.mutation "aaaaaaaaaaaaaaaa", subject: "Foo#bar", reason: "r"' }

  it "names the file when the source does not parse" do
    expect(refusal("def (")).to eq("config/saboteur_ignore.rb does not parse")
  end

  it "names the file when there is no block at all" do
    expect(refusal("")).to eq("config/saboteur_ignore.rb holds no Saboteur.ignore block")
  end

  [
    "Foo.ignore { |i| }",
    "Saboteur.other { |i| }",
    "Saboteur.ignore(1) { |i| }",
    "ignore { |i| }",
    "Saboteur::Inner.ignore { |i| }",
    "Saboteur.ignore",
    "42"
  ].each do |statement|
    it "refuses #{statement.inspect} as not a Saboteur.ignore block" do
      expect(refusal(statement)).to eq(
        "config/saboteur_ignore.rb must hold only Saboteur.ignore blocks, nothing else"
      )
    end
  end

  [
    'Saboteur.ignore { |i| i.other "aaaaaaaaaaaaaaaa", subject: "F", reason: "r" }',
    'Saboteur.ignore { |i| i.mutation("aaaaaaaaaaaaaaaa", subject: "F", reason: "r") { } }',
    'Saboteur.ignore { mutation "aaaaaaaaaaaaaaaa", subject: "F", reason: "r" }',
    'Saboteur.ignore { |i| Foo.mutation "aaaaaaaaaaaaaaaa", subject: "F", reason: "r" }',
    'Saboteur.ignore { |i, j| j.mutation "aaaaaaaaaaaaaaaa", subject: "F", reason: "r" }',
    'Saboteur.ignore { |i| mutation "aaaaaaaaaaaaaaaa", subject: "F", reason: "r" }',
    "Saboteur.ignore { |i| 42 }"
  ].each do |source|
    it "refuses #{source} as more than i.mutation entries" do
      expect(refusal(source)).to start_with("config/saboteur_ignore.rb holds more than i.mutation entries: ")
    end
  end

  it "shows the first 40 characters of the offending statement, no more and no fewer" do
    statement = "Kernel.system(\"#{'x' * 60}\")"
    expect(refusal("Saboteur.ignore { |i| #{statement} }")).to eq(
      "config/saboteur_ignore.rb holds more than i.mutation entries: #{statement[0, 40].inspect}..."
    )
  end

  it "reads an empty block, a block without parameters and the first of several parameters" do
    expect(described_class.parse("Saboteur.ignore { }")).to eq([])
    expect(described_class.parse("Saboteur.ignore { |i, j| #{entry_line} }").map(&:mutation))
      .to eq(["aaaaaaaaaaaaaaaa"])
  end

  it "refuses an entry in a block without parameters" do
    expect(refusal("Saboteur.ignore { #{entry_line} }")).to start_with("config/saboteur_ignore.rb holds more than")
  end

  it "refuses an entry with no arguments at all" do
    expect(refusal("Saboteur.ignore { |i| i.mutation }")).to eq(
      "config/saboteur_ignore.rb entry has non-literal or unknown arguments"
    )
  end

  it "refuses an entry with unknown keywords" do
    expect(refusal('Saboteur.ignore { |i| i.mutation "aaaaaaaaaaaaaaaa", subject: "F", reason: "r", extra: "x" }'))
      .to eq("config/saboteur_ignore.rb entry has non-literal or unknown arguments")
  end

  it "reports every missing keyword by name" do
    expect(refusal('Saboteur.ignore { |i| i.mutation "aaaaaaaaaaaaaaaa" }')).to eq(
      "config/saboteur_ignore.rb entry is missing subject, reason"
    )
  end

  it "refuses a second positional argument" do
    expect(refusal('Saboteur.ignore { |i| i.mutation "aaaaaaaaaaaaaaaa", "b", subject: "F", reason: "r" }')).to eq(
      "config/saboteur_ignore.rb entry takes one digest plus literal keywords"
    )
  end

  it "refuses a splat mixed with literal keywords" do
    source = 'Saboteur.ignore { |i| i.mutation "aaaaaaaaaaaaaaaa", subject: "F", **{ reason: "r" } }'
    expect(refusal(source)).to eq("config/saboteur_ignore.rb entry takes one digest plus literal keywords")
  end
end

RSpec.describe IgnoreAudit::StaticEntries, "partial literals" do
  it "refuses a digest that mixes literal text with interpolation" do
    source = <<-'RUBY'
      Saboteur.ignore do |i|
        i.mutation "aaaa#{'a' * 12}", subject: "Foo#bar", reason: "r"
      end
    RUBY
    expect { described_class.parse(source) }.to raise_error(
      IgnoreAudit::Incomplete, "config/saboteur_ignore.rb entry has non-literal or unknown arguments"
    )
  end
end

RSpec.describe IgnoreAudit::Resolver, "project config" do
  def write_project(dir, config_body, source)
    FileUtils.mkdir_p(File.join(dir, "src"))
    FileUtils.mkdir_p(File.join(dir, "config"))
    File.write(File.join(dir, "src", "widget.rb"), source)
    File.write(File.join(dir, "config", "saboteur.rb"), "Saboteur.configure do |c|\n#{config_body}\nend\n")
  end

  def digest_at(dir, subject_id, index)
    config = Saboteur::Config.load(root: dir)
    guard = Saboteur::MutationSource::HazardGuard.new(config["hazard"])
    candidates = Saboteur::Engine::Candidates.build(config, Saboteur::Engine::Diagnostics.new(StringIO.new),
                                                    hazard_guard: guard)
    file = File.join(dir, "src", "widget.rb")
    subject = Saboteur::SubjectFinder.new.call(file).subjects.find { |item| item.id == subject_id }
    mutation, = candidates.for(subject)[index]
    mutation.digest(subject_start: subject.start_byte, original_source: subject.file_source)
  end

  it "reads the include patterns from the root it is given, not the working directory" do
    Dir.mktmpdir do |dir|
      write_project(dir, '  c.include = ["src/**/*.rb"]', "class Widget\n  def big?(x)\n    x > 3\n  end\nend\n")
      entry = Saboteur::IgnoreList::Entry.new(subject: "Widget#big?", mutation: digest_at(dir, "Widget#big?", 0),
                                              reason: "x")
      expect(described_class.new(root: dir).live?(entry)).to be(true)
    end
  end

  it "follows the project's hazard list, so an emptied list keeps mutants of a destructive call" do
    Dir.mktmpdir do |dir|
      write_project(dir, "  c.include = [\"src/**/*.rb\"]\n  c.hazard = []",
                    "class Widget\n  def run(x)\n    system(\"echo\", x)\n  end\nend\n")
      entry = Saboteur::IgnoreList::Entry.new(subject: "Widget#run", mutation: digest_at(dir, "Widget#run", -1),
                                              reason: "x")
      expect(described_class.new(root: dir).live?(entry)).to be(true)
    end
  end
end

RSpec.describe IgnoreAudit::KillProof, "spec target" do
  it "takes the first config rspec_args entry that is not a flag" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "saboteur.rb"), <<~RUBY)
        Saboteur.configure do |c|
          c.rspec_args = ["--fail-fast", "spec/my-dir", "spec/other"]
        end
      RUBY
      expect(described_class.new(root: dir).send(:spec)).to eq("spec/my-dir")
    end
  end
end
