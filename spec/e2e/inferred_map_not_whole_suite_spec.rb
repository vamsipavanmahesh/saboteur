# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"

# #1286: a map built from inferred specs holds only the specs matched to a
# source file. It used to be recorded as the whole-suite map, so a scoped
# run read it back and printed "ran, still passed" next to a survivor that
# a spec outside the selection (one with no matching source file) kills.
RSpec.describe "an inferred-spec map is not the whole-suite map", :e2e do
  let(:dir) { copy_fixture("people") }
  let(:unconfirmed_line) do
    "saboteur: survivors unconfirmed: no whole-suite coverage map; run `saboteur run --all` to build one"
  end

  def git(*args)
    _out, err, status = Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
    raise err unless status.success?
  end

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
    File.write(File.join(dir, path), text)
  end

  def pointer = File.join(dir, ".saboteur", "whole-suite-map-v2")

  before do
    write("lib/ledger/router.rb", <<~RUBY)
      module Ledger
        class Router
          def lane(amount) = amount > 5_000_000 ? "review" : "auto"
        end
      end
    RUBY
    # Weak: the line runs, the answer is never compared.
    write("spec/ledger/router_spec.rb", <<~RUBY)
      require_relative "../../lib/ledger/router"

      RSpec.describe Ledger::Router do
        it("answers a lane") { expect(described_class.new.lane(10)).to be_a(String) }
      end
    RUBY
    # The real pin lives in a spec no source file name maps to.
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
  end

  it "writes no pointer after an inferred run, so a scoped run says its survivors are unconfirmed" do
    inferred = saboteur(dir)
    expect(inferred.json).not_to be_nil
    expect(File.exist?(pointer)).to be(false)

    run = saboteur(dir, "--since", "HEAD")

    expect(run.status).to eq(1), run.out + run.err
    expect(run.err.scan(unconfirmed_line).size).to eq(1)
    expect(run.out).to include("covering list is this run's selection only")
    expect(run.out).not_to include("ran, still passed")
    expect(run.out).not_to include("pins this line")
  end

  it "keeps the pointer after run --all, and the scoped run names the spec it did not load" do
    saboteur(dir, "--all")
    expect(File.exist?(pointer)).to be(true)

    run = saboteur(dir, "--since", "HEAD")

    expect(run.err).not_to include("survivors unconfirmed")
    expect(run.out).to include("flow_spec.rb")
    expect(run.out).to include("confirmed: ./spec/integration/flow_spec.rb[1:")
    expect(run.out).to include("ran on confirmation and still passed")
    expect(run.out).not_to include("(not run here)")
    expect(run.out).not_to include("likely covered elsewhere")
  end

  it "prints the unconfirmed notice once under --quiet" do
    run = saboteur(dir, "--since", "HEAD", "--quiet")

    expect(run.err.scan(unconfirmed_line).size).to eq(1)
  end
end
