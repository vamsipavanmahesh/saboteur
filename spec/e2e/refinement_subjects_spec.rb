# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"

# A file that uses refinements has every subject skipped (re-eval of a
# refined method is unsafe). When the whole --since diff lives in such a
# file the run used to exit 0 with score n/a - a green run that tested
# nothing. Now it exits 3 and names the skipped subjects, and a partially
# skipped diff announces the skip up front (#574).
RSpec.describe "saboteur run --since: subjects skipped for refinements", :e2e do
  let(:dir) { copy_fixture("people") }

  def git(*args)
    _out, err, status = Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
    raise err unless status.success?
  end

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
    File.write(File.join(dir, path), text)
  end

  def change_greeting
    write("lib/greeter.rb", File.read(File.join(dir, "lib/greeter.rb")).sub('"hi ', '"hello '))
    write("spec/greeter_spec.rb", File.read(File.join(dir, "spec/greeter_spec.rb")).sub('"hi BOB"', '"hello BOB"'))
  end

  before do
    write("lib/shout_ext.rb", <<~RUBY)
      module ShoutExt
        refine String do
          def shout = upcase
        end
      end
    RUBY
    write("lib/greeter.rb", <<~RUBY)
      require_relative "shout_ext"
      using ShoutExt

      class Greeter
        def greet(name) = "hi \#{name.shout}"
      end
    RUBY
    write("spec/greeter_spec.rb", <<~RUBY)
      require_relative "../lib/greeter"

      RSpec.describe Greeter do
        it("greets") { expect(described_class.new.greet("bob")).to eq("hi BOB") }
      end
    RUBY
    write("lib/adder.rb", <<~RUBY)
      class Adder
        def add(left, right) = left + right
      end
    RUBY
    write("spec/adder_spec.rb", <<~RUBY)
      require_relative "../lib/adder"

      RSpec.describe Adder do
        it("adds") { expect(described_class.new.add(1, 2)).to eq(3) }
      end
    RUBY
    git("init", "-q")
    git("add", ".")
    git("commit", "-q", "-m", "base")
  end

  it "exits 3 and names the skipped subject when the whole diff is unverifiable" do
    change_greeting
    run = saboteur(dir, "--since", "HEAD")

    expect(run.status).to eq(3)
    expect(run.err).to include("error: Greeter#greet (lib/greeter.rb:5) was skipped (refinements), " \
                               "so the change under test was not verified\n" \
                               "help: run the specs that exercise it, or narrow the scope past it")
  end

  it "runs the verifiable part of a partially skipped diff, with a loud warning" do
    change_greeting
    write("lib/adder.rb", File.read(File.join(dir, "lib/adder.rb")).sub("left + right", "right + left"))
    run = saboteur(dir, "--since", "HEAD")

    expect(run.err).to include("Greeter#greet (lib/greeter.rb:5): skipped (refinements); " \
                               "its change is not verified by this run")
    expect(mutants(run)).not_to be_empty
  end
end
