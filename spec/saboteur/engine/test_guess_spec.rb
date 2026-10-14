# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require "tmpdir"

RSpec.describe Saboteur::Engine::TestGuess do
  let(:base_source) { "class Widget\n  def thing\n    1\n  end\nend\n" }
  let(:changed_source) { "class Widget\n  def thing\n    2\n  end\nend\n" }
  let(:dir) { File.realpath(Dir.mktmpdir("saboteur-guess")) }

  after { FileUtils.remove_entry(dir) }

  def git(*args)
    Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
  end

  def write(path, text = "# x\n")
    FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
    File.write(File.join(dir, path), text)
  end

  def guess(include: ["lib/**/*.rb", "app/**/*.rb", "src/**/*.rb"])
    config = Saboteur::Config.new({ "since" => "HEAD", "include" => include }, root: dir)
    described_class.new(config).call
  end

  before do
    git("init", "-q")
    %w[lib/a.rb lib/deep/b.rb lib/c.rb app/models/d.rb lib/e.rb].each { |file| write(file, base_source) }
    %w[spec/a_spec.rb spec/deep/b_spec.rb spec/models/d_spec.rb spec/lib/e_spec.rb spec/stray_spec.rb].each do |f|
      write(f)
    end
    git("add", ".")
    git("commit", "-q", "-m", "base")
  end

  it "finds the spec named after each changed source file" do
    %w[lib/a.rb lib/deep/b.rb app/models/d.rb lib/e.rb].each { |file| write(file, changed_source) }
    result = guess
    expect(result.specs).to eq(%w[spec/a_spec.rb spec/deep/b_spec.rb spec/lib/e_spec.rb spec/models/d_spec.rb])
    expect([result.unmatched, result.changed]).to eq([[], 4])
  end

  it "names the changed files that have no spec" do
    write("lib/a.rb", changed_source)
    write("lib/c.rb", changed_source)
    result = guess
    expect([result.specs, result.unmatched, result.changed]).to eq([["spec/a_spec.rb"], ["lib/c.rb"], 2])
  end

  it "ignores changed files that saboteur would not mutate" do
    write("lib/a.rb", changed_source)
    write("spec/stray_spec.rb", "# changed\n")
    result = guess
    expect([result.specs, result.unmatched, result.changed]).to eq([["spec/a_spec.rb"], [], 1])
  end

  it "only drops the lib or app directory when guessing, not any first directory" do
    write("src/f.rb", base_source)
    write("spec/f_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "more")
    write("src/f.rb", changed_source)
    expect(guess.unmatched).to eq(["src/f.rb"])
  end

  it "does not treat a root file named lib as a source directory" do
    write("lib.rb", base_source)
    write("spec/lib/lib_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "root file")
    write("lib.rb", changed_source)
    expect(guess(include: ["lib.rb"]).unmatched).to eq(["lib.rb"])
  end

  context "with Rails request specs" do
    before do
      write("app/controllers/users_controller.rb", base_source)
      write("app/controllers/api/orders_controller.rb", base_source)
      write("app/controllers/api/items_controller.rb", base_source)
      write("spec/requests/users_spec.rb")
      write("spec/requests/api/orders_controller_spec.rb")
      write("spec/requests/api/items_spec.rb")
      write("spec/requests/api/items_controller_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "controllers")
    end

    it "maps a controller to its request spec with or without the controller suffix" do
      %w[users api/orders api/items].each { |name| write("app/controllers/#{name}_controller.rb", changed_source) }
      result = guess
      expect(result.specs).to eq(%w[spec/requests/api/items_controller_spec.rb
                                    spec/requests/api/orders_controller_spec.rb spec/requests/users_spec.rb])
      expect(result.unmatched).to eq([])
    end

    it "prefers a controller spec over a request spec" do
      write("spec/controllers/users_controller_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "ctrl spec")
      write("app/controllers/users_controller.rb", changed_source)
      expect(guess.specs).to eq(["spec/controllers/users_controller_spec.rb"])
    end
  end

  context "with packwerk packs" do
    before do
      write("packs/billing/package.yml", "enforce_dependencies: true\n")
      write("packs/billing/app/models/invoice.rb", base_source)
      write("packs/billing/app/controllers/invoices_controller.rb", base_source)
      write("packs/billing/lib/tax.rb", base_source)
      write("packs/billing/app/models/orphan.rb", base_source)
      write("packs/billing/spec/models/invoice_spec.rb")
      write("packs/billing/spec/requests/invoices_spec.rb")
      write("packs/billing/spec/tax_spec.rb")
      write("spec/models/orphan_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "packs")
    end

    it "maps a pack file to the spec inside the same pack" do
      %w[app/models/invoice app/controllers/invoices_controller lib/tax].each do |name|
        write("packs/billing/#{name}.rb", changed_source)
      end
      result = guess(include: ["packs/**/*.rb"])
      expect(result.specs).to eq(%w[packs/billing/spec/models/invoice_spec.rb
                                    packs/billing/spec/requests/invoices_spec.rb
                                    packs/billing/spec/tax_spec.rb])
      expect(result.unmatched).to eq([])
    end

    it "does not borrow a spec from another pack or the root" do
      write("packs/billing/app/models/orphan.rb", changed_source)
      expect(guess(include: ["packs/**/*.rb"]).unmatched).to eq(["packs/billing/app/models/orphan.rb"])
    end

    it "finds packs at any depth from package.yml, not a hardcoded packs directory" do
      write("components/ledger/package.yml")
      write("components/ledger/app/models/entry.rb", base_source)
      write("components/ledger/spec/models/entry_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "ledger")
      write("components/ledger/app/models/entry.rb", changed_source)
      expect(guess(include: ["components/**/*.rb"]).specs).to eq(["components/ledger/spec/models/entry_spec.rb"])
    end
  end

  it "lists candidates most specific first, with the lib variant before the full stem" do
    guesser = described_class.new(Saboteur::Config.new({}, root: dir))
    expect(guesser.send(:candidates_for, "app/models/user.rb"))
      .to eq(["spec/models/user_spec.rb", "spec/lib/models/user_spec.rb", "spec/app/models/user_spec.rb"])
    expect(guesser.send(:candidates_for, "lib/a/b.rb"))
      .to eq(["spec/a/b_spec.rb", "spec/lib/a/b_spec.rb"])
  end

  it "adds request spec names only for controllers" do
    guesser = described_class.new(Saboteur::Config.new({}, root: dir))
    expect(guesser.send(:request_names, "models/user")).to eq([])
    expect(guesser.send(:request_names, "controllers/api/users_controller"))
      .to eq(["requests/api/users_controller", "requests/api/users"])
  end

  it "detects pack directories once per run" do
    guesser = described_class.new(Saboteur::Config.new({}, root: dir))
    expect(Dir).to receive(:glob).with("**/package.yml", base: dir).once.and_return([])
    2.times { guesser.send(:pack_dirs) }
  end

  it "does not require a spec for a file whose changed lines touch no method" do
    write("lib/c.rb", "class Widget\n  def thing\n    1\n  end\nend\n\n# a tail note\n")
    git("add", ".")
    git("commit", "-q", "-m", "tail note")
    write("lib/c.rb", "class Widget\n  def thing\n    1\n  end\nend\n\n# a better tail note\n")
    result = guess
    expect([result.specs, result.unmatched, result.subjectless, result.changed]).to eq([[], [], ["lib/c.rb"], 1])
  end

  it "does not require a spec for a deletion whose remaining context lines touch no method" do
    write("lib/c.rb", "# errors\n\nclass FooError < StandardError\nend\n\nclass BarError < StandardError\nend\n")
    git("add", ".")
    git("commit", "-q", "-m", "error classes")
    write("lib/c.rb", "# errors\n\nclass BarError < StandardError\nend\n")
    result = guess
    expect([result.unmatched, result.subjectless]).to eq([[], ["lib/c.rb"]])
  end

  it "does not require a spec when the changed method differs only in comments" do
    write("lib/c.rb", "class Widget\n  def thing\n    # a note\n    1\n  end\nend\n")
    git("add", ".")
    git("commit", "-q", "-m", "note")
    write("lib/c.rb", "class Widget\n  def thing\n    # a better note\n    1\n  end\nend\n")
    expect(guess.subjectless).to eq(["lib/c.rb"])
  end

  it "still requires specs for the other files when one change touches no method" do
    write("lib/a.rb", changed_source)
    write("lib/c.rb", "class Widget\n  def thing\n    1\n  end\nend\n\n# a tail note\n")
    result = guess
    expect([result.specs, result.unmatched, result.subjectless, result.changed])
      .to eq([["spec/a_spec.rb"], [], ["lib/c.rb"], 2])
  end

  it "does not guess a spec for a file with no changed mutation subjects" do
    write("spec/c_spec.rb")
    write("lib/c.rb", "class Widget\n  def thing\n    # a note\n    1\n  end\nend\n")
    git("add", ".")
    git("commit", "-q", "-m", "c with spec")
    write("lib/c.rb", "class Widget\n  def thing\n    # a better note\n    1\n  end\nend\n")
    result = guess
    expect([result.specs, result.unmatched, result.subjectless]).to eq([[], [], ["lib/c.rb"]])
  end

  it "falls back for a subjectful file without a spec when the other change is subjectless with a spec" do
    write("lib/a.rb", "class Widget\n  def thing\n    # a better note\n    1\n  end\nend\n")
    write("lib/c.rb", "class Widget\n  def thing\n    2\n  end\nend\n")
    result = guess
    expect([result.specs, result.unmatched, result.subjectless]).to eq([[], ["lib/c.rb"], ["lib/a.rb"]])
  end

  it "lists a spec guessed for two changed files once" do
    write("lib/deep/dup.rb", base_source)
    write("deep/dup.rb", base_source)
    write("spec/deep/dup_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "two files one spec")
    write("lib/deep/dup.rb", changed_source)
    write("deep/dup.rb", changed_source)
    result = guess(include: ["lib/**/*.rb", "deep/**/*.rb"])
    expect(result.specs).to eq(["spec/deep/dup_spec.rb"])
  end

  it "lists unmatched files sorted, however git ordered the diff" do
    write("lib/z.rb", base_source)
    git("add", ".")
    git("commit", "-q", "-m", "z")
    write("lib/c.rb", changed_source)
    write("lib/z.rb", changed_source)
    lines = { File.join(dir, "lib/z.rb") => Set[3], File.join(dir, "lib/c.rb") => Set[3] }
    allow(Saboteur::Selection::GitDiff).to receive(:changed_lines).and_return(lines)
    expect(guess.unmatched).to eq(["lib/c.rb", "lib/z.rb"])
  end

  it "stays subjectless when a comment added above a method shifts its __LINE__" do
    write("lib/c.rb", "class Widget\n  def thing\n    __LINE__\n  end\nend\n")
    git("add", ".")
    git("commit", "-q", "-m", "line marker")
    write("lib/c.rb", "# a note\nclass Widget\n  def thing\n    __LINE__\n  end\nend\n")
    result = guess
    expect([result.unmatched, result.subjectless]).to eq([[], ["lib/c.rb"]])
  end

  it "reports nothing changed" do
    expect(guess.changed).to eq(0)
  end
end
