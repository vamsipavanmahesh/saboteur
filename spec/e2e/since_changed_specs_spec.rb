# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"

# A pull request often tests a change through a request or controller spec
# whose name maps to no changed file. With --since, every spec the diff adds
# or changes runs next to the inferred ones, so a mutant only that spec
# kills is not a false survivor (#307).
RSpec.describe "saboteur run --since: specs changed in the diff", :e2e do
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
    write("lib/serializer.rb", <<~RUBY)
      class Serializer
        def self.status(code) = code.zero? ? "ok" : "failed"
      end
    RUBY
    # The inferred spec executes the changed line but checks only the ok
    # branch, so a mutant of the error value survives it.
    write("spec/serializer_spec.rb", <<~RUBY)
      require_relative "../lib/serializer"

      RSpec.describe Serializer do
        it("answers ok") { expect(described_class.status(0)).to eq("ok") }
      end
    RUBY
    git("init", "-q")
    git("add", ".")
    git("commit", "-q", "-m", "base")
    write("lib/serializer.rb", File.read(File.join(dir, "lib/serializer.rb")).sub('"failed"', '"error"'))
  end

  it "kills a mutant through a spec the diff adds, whose name maps to no changed file" do
    write("spec/requests/status_spec.rb", <<~RUBY)
      require_relative "../../lib/serializer"

      RSpec.describe "GET /status" do
        it("reports ok") { expect(Serializer.status(0)).to eq("ok") }
        it("reports an error") { expect(Serializer.status(1)).to eq("error") }
      end
    RUBY
    # --verbose: the paragraph with the changed-in-the-diff annotation is
    # verbose-only since the quiet start (PR4) folds it into a count line.
    run = saboteur(dir, "--since", "HEAD", "--verbose")

    statuses = mutants(run).map { |m| m["status"] }
    expect(statuses).not_to be_empty
    expect(statuses).not_to include("Survived")
    expect(run.err).to include("inferred specs: running only spec/requests/status_spec.rb, " \
                               "spec/serializer_spec.rb (changed in the diff: spec/requests/status_spec.rb)")
  end

  it "names a spec the diff deletes instead of running it" do
    File.delete(File.join(dir, "spec", "stage_slow_spec.rb"))
    # --verbose: the inferred-specs paragraph is verbose-only since PR4.
    run = saboteur(dir, "--since", "HEAD", "--verbose")

    expect(run.err).to include("inferred specs: not running spec files changed in the diff: " \
                               "spec/stage_slow_spec.rb (deleted in the diff)")
    expect(run.err).to include("inferred specs: running only spec/serializer_spec.rb.")
  end
end
