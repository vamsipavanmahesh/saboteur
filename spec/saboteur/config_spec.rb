# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Config do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def write(path, content)
    full = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  it "uses defaults without a config file" do
    config = described_class.load(root: @root)
    expect(config.to_h.values_at("integration", "timeout_factor", "timeout_min", "jobs", "reeval"))
      .to eq(["rspec", 3.0, 5.0, 1, "class_eval"])
  end

  it "reads .saboteur.yml and lets CLI overrides win" do
    write(".saboteur.yml", "timeout_factor: 4\njobs: 1\nreeval: nesting\n")
    config = described_class.load(root: @root, overrides: { timeout_factor: 2.5, since: nil })
    expect([config["timeout_factor"], config["reeval"], config["since"]]).to eq([2.5, "nesting", nil])
  end

  it "resolves include and exclude globs to real paths of .rb files" do
    write("lib/a.rb", "")
    write("lib/b.rb", "")
    write("lib/version.rb", "")
    write("lib/notes.txt", "")
    config = described_class.new({ "include" => ["lib/**/*"], "exclude" => ["lib/version.rb"] }, root: @root)
    expect(config.included_files).to eq(%w[a.rb b.rb].map { |f| File.join(@root, "lib", f) })
  end

  it "names include and exclude patterns that match no file, so a stale path is never silent" do
    write("lib/a.rb", "")
    config = described_class.new({ "include" => ["lib/**/*.rb", "app/**/*.rb"],
                                   "exclude" => ["lib/a.rb", "lib/moved.rb"] }, root: @root)
    expect(config.unmatched_patterns).to eq(["include: app/**/*.rb", "exclude: lib/moved.rb"])
  end

  it "rejects unknown keys, bad values and bad arid patterns" do
    expect { described_class.new({ "timeout" => 1 }) }.to raise_error(Saboteur::Error, /unknown config key/)
    expect { described_class.new({ "jobs" => "many" }) }.to raise_error(Saboteur::Error, /invalid config value/)
    expect { described_class.new({ "jobs" => 0 }) }.to raise_error(Saboteur::Error, /jobs/)
    expect { described_class.new({ "arid" => ["("] }) }.to raise_error(Saboteur::Error, /arid/)
    expect { described_class.new({ "reeval" => "eval" }) }.to raise_error(Saboteur::Error, /reeval/)
  end

  it "reports YAML errors with the file name" do
    write(".saboteur.yml", "include: [\n")
    expect { described_class.load(root: @root) }.to raise_error(Saboteur::Error, /\.saboteur\.yml/)
  end

  it "expands paths relative to the root" do
    expect(described_class.new({}, root: @root).path("ignore_file")).to eq(File.join(@root, ".saboteur-ignore.yml"))
  end
end
