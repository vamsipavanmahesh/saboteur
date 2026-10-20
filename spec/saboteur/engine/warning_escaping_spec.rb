# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# A repository controls file names, map entries and grants. A name with a
# newline must not start a line with "::" or "##[" in a warning, where the
# GitHub Actions runner would read it as a workflow command (#834).
RSpec.describe "warnings built from repo-controlled text" do
  let(:hostile) { "x\n::error::injected" }

  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def commands_in(warnings)
    warnings.flat_map { |warning| warning.to_s.lines }.select { |line| line.lstrip.start_with?("::", "##[") }
  end

  it "escapes a file name in the syntax warning" do
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    file = File.join(@root, "#{hostile}.rb")
    File.write(file, "def nope(\n")
    config = Saboteur::Config.new({}, root: @root)
    Saboteur::Engine::SubjectSelection.new(config, diagnostics).select([file])

    expect(diagnostics.warnings).to include(a_string_matching(/fix the syntax in x/))
    expect(commands_in(diagnostics.warnings)).to be_empty
  end

  it "escapes custom map names in the no-match warning" do
    warned = []
    diagnostics = instance_double(Saboteur::Engine::Diagnostics)
    allow(diagnostics).to receive(:warn) { |message| warned << message }
    guess = Saboteur::Engine::TestGuess.new(Saboteur::Config.new({}, root: @root), diagnostics: diagnostics)
    guess.send(:expand_mapped, "#{hostile}.rb", ["spec/#{hostile}_spec.rb"])

    expect(warned).not_to be_empty
    expect(commands_in(warned)).to be_empty
  end

  it "escapes a granted directory in the redundant-grant warning" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
    config = Saboteur::Config.new({ "sandbox_writable" => ["data", "data/#{hostile}"] }, root: @root)
    engine = Saboteur::Engine.new(config, err: StringIO.new)
    engine.send(:sandbox_hook)

    warnings = engine.instance_variable_get(:@diagnostics).warnings
    expect(warnings).to include(a_string_matching(/redundant sandbox grant/))
    expect(commands_in(warnings)).to be_empty
  end

  it "escapes the parent directory too in the redundant-grant warning" do
    allow(Saboteur::Execution::Sandbox).to receive(:abi_version).and_return(3)
    parent = "data/#{hostile}"
    config = Saboteur::Config.new({ "sandbox_writable" => [parent, "#{parent}/nested"] }, root: @root)
    engine = Saboteur::Engine.new(config, err: StringIO.new)
    engine.send(:sandbox_hook)

    warnings = engine.instance_variable_get(:@diagnostics).warnings
    expect(warnings).to include(a_string_matching(/redundant sandbox grant/))
    expect(commands_in(warnings)).to be_empty
  end

  it "escapes the parser's message in the syntax warning" do
    diagnostics = Saboteur::Engine::Diagnostics.new(StringIO.new)
    file = File.join(@root, "broken.rb")
    File.write(file, "def nope(\n")
    found = Struct.new(:errors, :subjects).new(["unexpected\n::error::from the file text"], [])
    allow_any_instance_of(Saboteur::SubjectFinder).to receive(:call).and_return(found)
    config = Saboteur::Config.new({}, root: @root)
    Saboteur::Engine::SubjectSelection.new(config, diagnostics).select([file])

    expect(diagnostics.warnings).to include(a_string_matching(/does not parse \(unexpected\\x0a::error::from/))
    expect(commands_in(diagnostics.warnings)).to be_empty
  end
end
