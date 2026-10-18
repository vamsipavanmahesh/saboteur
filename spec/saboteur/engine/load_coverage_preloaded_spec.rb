# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Engine::LoadCoverage, "files loaded before Coverage.start" do
  before { allow(Coverage).to receive(:state).and_return(:suspended) }

  it "names include-listed files that are loaded but carry no coverage instrumentation" do
    allow(Saboteur::CoverageReads).to receive(:result).and_return("/app/lib/kept.rb" => {})
    files = ["/app/lib/kept.rb", "/app/lib/early.rb"]

    expect(described_class.preloaded_uninstrumented(files, loaded: ["/app/lib/kept.rb", "/app/lib/early.rb"]))
      .to eq(["/app/lib/early.rb"])
  end

  it "ignores files that were never loaded and files outside the include list" do
    allow(Saboteur::CoverageReads).to receive(:result).and_return({})

    expect(described_class.preloaded_uninstrumented(["/app/lib/mine.rb"], loaded: ["/gems/other/lib/x.rb"]))
      .to eq([])
  end

  it "reads the running snapshot without stopping or clearing it (a stop would break a later --test run)" do
    allow(Saboteur::CoverageReads).to receive(:result).and_return("/app/lib/kept.rb" => {})

    described_class.preloaded_uninstrumented(["/app/lib/kept.rb"], loaded: [])

    expect(Saboteur::CoverageReads).to have_received(:result).with(stop: false, clear: false)
  end

  it "matches files under any spelling of their path (symlinked root)" do
    Dir.mktmpdir do |dir|
      Dir.mkdir(File.join(dir, "real"))
      # Realpath the direct spelling: the matcher returns canonical paths,
      # and on macOS the tmpdir itself sits behind /var -> /private/var.
      File.write(File.join(dir, "real", "a.rb"), "1\n")
      target = File.realpath(File.join(dir, "real", "a.rb"))
      File.symlink(File.join(dir, "real"), File.join(dir, "link"))
      spelled = File.join(dir, "link", "a.rb")
      allow(Saboteur::CoverageReads).to receive(:result).and_return({})

      expect(described_class.preloaded_uninstrumented([spelled], loaded: [target])).to eq([target])
      expect(described_class.preloaded_uninstrumented([target], loaded: [spelled])).to eq([target])
    end
  end

  it "lists a file once when the include list spells the same path twice (run dir and symlink)" do
    Dir.mktmpdir do |dir|
      Dir.mkdir(File.join(dir, "real"))
      File.write(File.join(dir, "real", "a.rb"), "1\n")
      target = File.realpath(File.join(dir, "real", "a.rb"))
      File.symlink(File.join(dir, "real"), File.join(dir, "link"))
      spelled = File.join(dir, "link", "a.rb")
      allow(Saboteur::CoverageReads).to receive(:result).and_return({})

      expect(described_class.preloaded_uninstrumented([target, spelled], loaded: [target])).to eq([target])
    end
  end

  it "is empty when coverage never started" do
    allow(Coverage).to receive(:state).and_return(:idle)

    expect(described_class.preloaded_uninstrumented(["/app/lib/x.rb"], loaded: ["/app/lib/x.rb"])).to eq([])
  end
end
