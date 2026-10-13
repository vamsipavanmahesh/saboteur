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

  it "reports nothing changed" do
    expect(guess.changed).to eq(0)
  end
end
