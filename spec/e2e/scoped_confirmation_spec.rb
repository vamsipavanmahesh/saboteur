# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"

# #1286: a scoped run (--since) selects only the specs next to the changed
# file, so a survivor can be pinned by a spec it never loaded. With a
# whole-suite map from `run --all`, each survivor's covering specs outside
# the selection get one budgeted run: a kill there is a real kill, a survivor
# that could not be checked is unconfirmed and outside score and exit code.
RSpec.describe "scoped runs confirm survivors against the whole-suite map", :e2e do
  let(:dir) { copy_fixture("people") }
  let(:budget) { 300 }

  def git(*args)
    _out, err, status = Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
    raise err unless status.success?
  end

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
    File.write(File.join(dir, path), text)
  end

  before do
    write("config/saboteur.rb", <<~RUBY)
      Saboteur.configure do |c|
        c.confirmation_budget = #{budget}
      end
    RUBY
    write("lib/ledger/router.rb", <<~RUBY)
      module Ledger
        class Router
          def lane(amount) = amount > 5_000_000 ? "review" : "auto"
        end
      end
    RUBY
    write("spec/ledger/router_spec.rb", <<~RUBY)
      require_relative "../../lib/ledger/router"

      RSpec.describe Ledger::Router do
        it("answers a lane") { expect(described_class.new.lane(10)).to be_a(String) }
      end
    RUBY
    write("spec/integration/flow_spec.rb", <<~RUBY)
      require_relative "../../lib/ledger/router"

      RSpec.describe "payment flow" do
        it("sends large amounts to review") { expect(Ledger::Router.new.lane(6_000_000)).to eq("review") }
        it("keeps the limit itself automatic") { expect(Ledger::Router.new.lane(5_000_000)).to eq("auto") }
      end
    RUBY
    git("init", "-q")
    git("add", ".")
    git("commit", "-q", "-m", "base")
    write("lib/ledger/router.rb", File.read(File.join(dir, "lib/ledger/router.rb")).sub("> 5_000_000", ">= 5_000_001"))
    saboteur(dir, "--all")
  end

  it "kills survivors on the spec the run did not load and credits that spec" do
    run = saboteur(dir, "--since", "HEAD")

    # Only the boundary mutants flow_spec cannot see stay live: 2 of 13 survive.
    expect(run.status).to eq(1), run.out + run.err
    expect(run.out).to include("Score: 84.6% (11/13 killed, tested subjects)")
    killed = mutants(run).select { |mutant| mutant["confirmation"] == "killed_by_confirmation" }
    expect(killed.size).to eq(9)
    expect(killed).to all(include("status" => "Killed"))
    names = run.json.fetch("testFiles").values.flat_map { |file| file.fetch("tests") }.to_h { |t| [t["id"], t["name"]] }
    credited = killed.map { |mutant| names.fetch(mutant["creditedTest"]) }
    expect(credited).to all(include("flow_spec.rb"))
    expect(mutants(run).count { |mutant| mutant["status"] == "Survived" }).to eq(2)
  end

  context "with the confirmation budget spent" do
    let(:budget) { 0 }

    it "keeps the survivors, lists them as unconfirmed and leaves them out of the score and the exit code" do
      run = saboteur(dir, "--since", "HEAD")

      expect(run.out).to include("unconfirmed (covering tests not run)")
      unconfirmed = mutants(run).select { |mutant| mutant["confirmation"] == "unconfirmed" }
      expect(unconfirmed).not_to be_empty
      expect(unconfirmed).to all(include("status" => "Ignored"))
      expect(run.out).to include("score 100.0%")
      expect(run.status).to eq(0), run.out + run.err
    end
  end

  it "keeps a survivor counted when the whole-suite map is drifted and cannot speak for its lines" do
    git("commit", "-q", "-am", "feature")
    saboteur(dir, "--all") # map now matches the committed tree
    router = File.join(dir, "lib/ledger/router.rb")
    shifted = "# one\n# two\n# three\n#{File.read(router).sub('>= 5_000_001', '>= 5_000_002')}"
    write("lib/ledger/router.rb", shifted)
    git("commit", "-q", "-am", "shift lines and move the limit")

    run = saboteur(dir, "--since", "HEAD~1")

    expect(run.status).to eq(1), run.out + run.err
    expect(run.out).not_to include("score 100.0%")
    expect(mutants(run).count { |mutant| mutant["status"] == "Survived" }).to be >= 1
    expect(run.out).to include("covers none of the edited lines")
  end

  context "with a poisoned whole-suite map naming a spec outside the project" do
    let(:outside) { Dir.mktmpdir("saboteur-evil") }
    let(:marker) { File.join(outside, "marker") }
    let(:evil) { File.join(outside, "evil_spec.rb") }

    before do
      File.write(evil, <<~RUBY)
        File.write(#{marker.inspect}, "ran")
        RSpec.describe("evil") { it("passes") { expect(1).to eq(1) } }
      RUBY
    end

    after { FileUtils.remove_entry(outside) }

    def poison(planted)
      Dir[File.join(dir, ".saboteur/coverage-*.json")].each do |path|
        map = JSON.parse(File.read(path))
        next unless map["tests"]

        map["tests"] = map["tests"].map { |id| id.include?("flow_spec") ? planted : id }
        File.write(path, JSON.generate(map))
      end
    end

    def relative_to_dir(path) = Pathname(path).relative_path_from(Pathname(File.realpath(dir))).to_s

    {
      "an absolute path" => ->(ctx) { "#{ctx.evil}[1:1]" },
      "a ../ path" => ->(ctx) { "#{ctx.relative_to_dir(ctx.evil)}[1:1]" },
      "a symlink out of the project" => lambda { |ctx|
        File.symlink(ctx.evil, File.join(ctx.dir, "spec/link_spec.rb"))
        "./spec/link_spec.rb[1:1]"
      }
    }.each do |label, planted|
      it "never loads #{label}, keeps the survivors counted and exits 1" do
        poison(planted.call(self))

        run = saboteur(dir, "--since", "HEAD")

        expect(File.exist?(marker)).to be(false), "planted spec was loaded"
        expect(run.status).to eq(1), run.out + run.err
        expect(run.out).to include("refused the whole-suite coverage map")
        expect(run.out).not_to include("score 100.0%")
        expect(mutants(run).count { |mutant| mutant["status"] == "Survived" }).to be >= 10
      end
    end
  end

  it "downgrades a confirmation that raises to unconfirmed with one warning, never exit 70" do
    # Committed, so --since does not select it: only the confirmation loads it.
    flow = File.join(dir, "spec/integration/flow_spec.rb")
    guard = "raise 'confirmation boom' if caller.any? { |line| line.include?('survivor_confirmation') }\n"
    write("spec/integration/flow_spec.rb", guard + File.read(flow))
    git("add", "spec")
    git("commit", "-q", "-m", "guard", "--", "spec")

    run = saboteur(dir, "--since", "HEAD")

    expect(run.status).not_to eq(70), run.out + run.err
    expect(run.out.scan("survivor confirmation failed for Ledger::Router#lane").size).to eq(1)
    expect(mutants(run).count { |mutant| mutant["confirmation"] == "unconfirmed" }).to be >= 1
    expect(run.out).to include("unconfirmed (covering tests not run)")
  end

  it "never exits 70 for run --all with partial_coverage use and two jobs (#1140)" do
    write("config/saboteur.rb", <<~RUBY)
      Saboteur.configure do |c|
        c.partial_coverage = "use"
      end
    RUBY
    git("commit", "-q", "-am", "x")
    saboteur(dir, "--all", "--jobs", "2")
    run = saboteur(dir, "--all", "--jobs", "2")

    expect(run.status).to be_between(0, 1), run.out + run.err
  end
end
