# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require "tmpdir"

RSpec.describe Saboteur::Engine::TestGuess do
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
    %w[lib/a.rb lib/deep/b.rb lib/c.rb app/models/d.rb lib/e.rb].each { |file| write(file, "1\n") }
    %w[spec/a_spec.rb spec/deep/b_spec.rb spec/models/d_spec.rb spec/lib/e_spec.rb spec/stray_spec.rb].each do |f|
      write(f)
    end
    git("add", ".")
    git("commit", "-q", "-m", "base")
  end

  it "finds the spec named after each changed source file" do
    %w[lib/a.rb lib/deep/b.rb app/models/d.rb lib/e.rb].each { |file| write(file, "2\n") }
    result = guess
    expect(result.specs).to eq(%w[spec/a_spec.rb spec/deep/b_spec.rb spec/lib/e_spec.rb spec/models/d_spec.rb])
    expect([result.unmatched, result.changed]).to eq([[], 4])
  end

  it "names the changed files that have no spec" do
    write("lib/a.rb", "2\n")
    write("lib/c.rb", "2\n")
    result = guess
    expect([result.specs, result.unmatched, result.changed]).to eq([["spec/a_spec.rb"], ["lib/c.rb"], 2])
  end

  it "ignores changed files that saboteur would not mutate" do
    write("lib/a.rb", "2\n")
    write("spec/stray_spec.rb", "# changed\n")
    result = guess
    expect([result.specs, result.unmatched, result.changed]).to eq([["spec/a_spec.rb"], [], 1])
  end

  it "only drops the lib or app directory when guessing, not any first directory" do
    write("src/f.rb", "1\n")
    write("spec/f_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "more")
    write("src/f.rb", "2\n")
    expect(guess.unmatched).to eq(["src/f.rb"])
  end

  it "does not treat a root file named lib as a source directory" do
    write("lib.rb", "1\n")
    write("spec/lib/lib_spec.rb")
    git("add", ".")
    git("commit", "-q", "-m", "root file")
    write("lib.rb", "2\n")
    expect(guess(include: ["lib.rb"]).unmatched).to eq(["lib.rb"])
  end

  context "with Rails request specs" do
    before do
      write("app/controllers/users_controller.rb", "1\n")
      write("app/controllers/api/orders_controller.rb", "1\n")
      write("app/controllers/api/items_controller.rb", "1\n")
      write("spec/requests/users_spec.rb")
      write("spec/requests/api/orders_controller_spec.rb")
      write("spec/requests/api/items_spec.rb")
      write("spec/requests/api/items_controller_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "controllers")
    end

    it "maps a controller to its request spec with or without the controller suffix" do
      %w[users api/orders api/items].each { |name| write("app/controllers/#{name}_controller.rb", "2\n") }
      result = guess
      expect(result.specs).to eq(%w[spec/requests/api/items_controller_spec.rb
                                    spec/requests/api/orders_controller_spec.rb spec/requests/users_spec.rb])
      expect(result.unmatched).to eq([])
    end

    it "prefers a controller spec over a request spec" do
      write("spec/controllers/users_controller_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "ctrl spec")
      write("app/controllers/users_controller.rb", "2\n")
      expect(guess.specs).to eq(["spec/controllers/users_controller_spec.rb"])
    end
  end

  context "with packwerk packs" do
    before do
      write("packs/billing/package.yml", "enforce_dependencies: true\n")
      write("packs/billing/app/models/invoice.rb", "1\n")
      write("packs/billing/app/controllers/invoices_controller.rb", "1\n")
      write("packs/billing/lib/tax.rb", "1\n")
      write("packs/billing/app/models/orphan.rb", "1\n")
      write("packs/billing/spec/models/invoice_spec.rb")
      write("packs/billing/spec/requests/invoices_spec.rb")
      write("packs/billing/spec/tax_spec.rb")
      write("spec/models/orphan_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "packs")
    end

    it "maps a pack file to the spec inside the same pack" do
      %w[app/models/invoice app/controllers/invoices_controller lib/tax].each do |name|
        write("packs/billing/#{name}.rb", "2\n")
      end
      result = guess(include: ["packs/**/*.rb"])
      expect(result.specs).to eq(%w[packs/billing/spec/models/invoice_spec.rb
                                    packs/billing/spec/requests/invoices_spec.rb
                                    packs/billing/spec/tax_spec.rb])
      expect(result.unmatched).to eq([])
    end

    it "does not borrow a spec from another pack or the root" do
      write("packs/billing/app/models/orphan.rb", "2\n")
      expect(guess(include: ["packs/**/*.rb"]).unmatched).to eq(["packs/billing/app/models/orphan.rb"])
    end

    it "finds packs at any depth from package.yml, not a hardcoded packs directory" do
      write("components/ledger/package.yml")
      write("components/ledger/app/models/entry.rb", "1\n")
      write("components/ledger/spec/models/entry_spec.rb")
      git("add", ".")
      git("commit", "-q", "-m", "ledger")
      write("components/ledger/app/models/entry.rb", "2\n")
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

  it "reports nothing changed" do
    expect(guess.changed).to eq(0)
  end
end
