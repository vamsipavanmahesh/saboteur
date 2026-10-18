# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"

# A partial --since mapping runs the mapped subset with a warning (#370),
# but a threshold or mutant-count gate judges the score, and the partial
# mapping narrows what the score covers: the unmapped file's mutants are
# skipped as NoCoverage and a perfect score of the rest passes the gate.
# A gated run keeps the hard stop instead (#370 review, #585).
RSpec.describe "saboteur run --since: partial mapping under a gate", :e2e do
  let(:dir) { copy_fixture("people") }

  def git(*args)
    _out, err, status = Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
    raise err unless status.success?
  end

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
    File.write(File.join(dir, path), text)
  end

  before do
    write("lib/alpha.rb", <<~RUBY)
      class Alpha
        def add(left, right) = left + right
      end
    RUBY
    write("spec/alpha_spec.rb", <<~RUBY)
      require_relative "../lib/alpha"

      RSpec.describe Alpha do
        it("adds") { expect(described_class.new.add(1, 2)).to eq(3) }
      end
    RUBY
    write("lib/beta.rb", <<~RUBY)
      class Beta
        def shout(word) = word.upcase
      end
    RUBY
    write("spec/beta_spec.rb", <<~RUBY)
      require_relative "../lib/beta"

      RSpec.describe Beta do
        it("shouts") { expect(described_class.new.shout("hi")).to eq("HI") }
      end
    RUBY
    git("init", "-q")
    git("add", ".")
    git("commit", "-q", "-m", "base")
    write("lib/alpha.rb", File.read(File.join(dir, "lib/alpha.rb")).sub("left + right", "right + left"))
    write("lib/beta.rb", File.read(File.join(dir, "lib/beta.rb")).sub("word.upcase", "word.upcase.strip"))
    write("spec/beta_spec.rb", File.read(File.join(dir, "spec/beta_spec.rb")).sub('"hi"', '"hi "'))
    File.delete(File.join(dir, "spec/beta_spec.rb"))
  end

  it "stops with exit 2 when a threshold is configured" do
    run = saboteur(dir, "--since", "HEAD", "--threshold", "100")

    expect(run.status).to eq(2)
    expect(run.err).to include("no spec found for lib/beta.rb")
  end

  it "runs the mapped subset with a loud warning when no gate is configured" do
    run = saboteur(dir, "--since", "HEAD")

    expect(run.err).to include("inferred specs: no spec found for lib/beta.rb")
    expect(mutants(run)).not_to be_empty
  end
end
