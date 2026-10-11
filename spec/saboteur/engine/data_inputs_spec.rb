# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"

RSpec.describe Saboteur::Engine::DataInputs do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def write(path, content = "x")
    full = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
    full
  end

  it "finds nothing in a project without Rails data files" do
    write("lib/a.rb")
    expect(described_class.files(@root)).to eq([])
  end

  it "finds fixtures, schema dumps and database config" do
    paths = %w[spec/fixtures/users.yml spec/models/fixtures/a.json test/fixtures/files/b.csv
               db/structure.sql db/schema.rb config/database.yml config/cable.yml]
    paths.each { |path| write(path) }
    write("app/models/user.rb")
    expect(described_class.files(@root)).to eq(paths.map { |path| File.join(@root, path) }.sort)
  end

  it "adds the configured extra globs" do
    write("data/seed.csv")
    write("data/other.txt")
    expect(described_class.files(@root, extra: ["data/*.csv"])).to eq([File.join(@root, "data/seed.csv")])
  end

  it "returns files only, never directories" do
    FileUtils.mkdir_p(File.join(@root, "spec/fixtures/empty_dir"))
    expect(described_class.files(@root)).to eq([])
  end
end
