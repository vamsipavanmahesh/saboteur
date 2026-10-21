# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"

# Real subprocess coverage for a non-UTF-8 locale (#231, #232): the CLI runs
# with LANG=C in a project whose root and changed source file are non-ASCII.
# The changed method must be found and mutated - if the locale broke
# selection, the run would silently mutate nothing and exit 0.
RSpec.describe "saboteur run under LANG=C with non-ASCII paths", :e2e do
  def git(dir, *args)
    _out, err, status = Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args,
                                       chdir: dir)
    raise err unless status.success?
  end

  def project
    root = File.join(Dir.mktmpdir("saboteur-e2e-"), "café")
    %w[lib spec config].each { |dir| FileUtils.mkdir_p(File.join(root, dir)) }
    File.write(File.join(root, "lib", "héllo.rb"), <<~RUBY)
      class Hello
        KIND = :greeter

        def greet
          "héllo"
        end
      end
    RUBY
    File.write(File.join(root, "spec", "hello_spec.rb"), <<~RUBY)
      require_relative "../lib/héllo"

      RSpec.describe Hello do
        it("greets") { expect(described_class.new.greet).to be_a(String) }
      end
    RUBY
    File.write(File.join(root, "config", "saboteur.rb"), <<~RUBY)
      Saboteur.configure do |c|
        c.include = ["lib/**/*.rb"]
        c.timeout_min = 10 # wall-time floor: fork boot under load, not test speed (#1129)
        # The accented source name maps to spec/hello_spec.rb, not the
        # conventional accented spec name, so inference would stop the run.
        c.test_selection = :all
      end
    RUBY
    root
  end

  def committed_project
    project.tap do |dir|
      git(dir, "init", "-q")
      git(dir, "add", ".")
      git(dir, "commit", "-q", "-m", "base")
    end
  end

  it "finds and reports a survivor in the changed non-ASCII file, exiting 1" do
    dir = committed_project
    path = File.join(dir, "lib", "héllo.rb")
    File.write(path, File.read(path, encoding: "UTF-8").sub("héllo", "héllö"))

    run = saboteur(dir, "--since", "HEAD", env: { "LANG" => "C", "LC_ALL" => "C" })
    expect(run.status).to eq(1), other_outcomes(run)
    expect(run.json.fetch("files").keys).to eq(["lib/héllo.rb"])
    expect(mutants(run).map { |m| m["status"] }).to include("Survived")
    expect(run.out).not_to include("no subjects covering")
  end

  it "warns when a changed Ruby file has no subjects, and still exits 0 (#232)" do
    dir = committed_project
    path = File.join(dir, "lib", "héllo.rb")
    File.write(path, File.read(path).sub("KIND = :greeter", "KIND = :welcomer"))

    run = saboteur(dir, "--since", "HEAD", env: { "LANG" => "C", "LC_ALL" => "C" })
    expect(run.status).to eq(0), other_outcomes(run)
    expect(run.out).to include("0 subjects, 0 mutants")
    expect(run.out).to include("warning: --since: 1 changed Ruby file(s) have no subjects covering the changed lines")
    expect(run.out).to include("héllo.rb")
  end
end
