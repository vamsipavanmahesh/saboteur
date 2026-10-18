# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Integration::RSpec, "load-error report (#608)" do
  # The shape RSpec 3 prints to stdout when a spec file raises at load,
  # captured from a real run: the suite's own frames, then the saboteur
  # frames the load was triggered through, then RSpec's reporter line.
  # The running tool's install root, the same way the filter computes it.
  let(:tool_root) { File.expand_path("../../..", __dir__) }

  let(:dump) do
    <<~TEXT

      An error occurred while loading ./spec/thing_spec.rb.
      Failure/Error: raise AppraisalNotSpecified, "specify an appraisal"

      AppraisalNotSpecified:
        specify an appraisal
      # ./spec/spec_helper.rb:3:in `<top (required)>'
      # ./spec/thing_spec.rb:1:in `<top (required)>'
      # #{tool_root}/lib/saboteur/integration/rspec.rb:18:in `setup'
      # #{tool_root}/lib/saboteur/engine/boot.rb:74:in `load_target'
      # #{tool_root}/exe/saboteur:34:in `<main>'
      No examples found.
    TEXT
  end

  def filter(text, verbose: false)
    described_class::LoadErrorReport.filter(text, verbose: verbose)
  end

  it "keeps the suite's own error: class, message and app frames" do
    report = filter(dump)
    expect(report).to include("An error occurred while loading ./spec/thing_spec.rb.")
    expect(report).to include("AppraisalNotSpecified:")
    expect(report).to include("specify an appraisal")
    expect(report).to include("# ./spec/spec_helper.rb:3:in `<top (required)>'")
    expect(report).to include("# ./spec/thing_spec.rb:1:in `<top (required)>'")
  end

  it "drops the saboteur frames the load was triggered through" do
    report = filter(dump)
    expect(report).not_to include("lib/saboteur/")
    expect(report).not_to include("exe/saboteur")
  end

  # The same lib/saboteur/ layout under ANOTHER root is the target's own
  # vendored copy or a dogfooded checkout: those frames are the suite's
  # and stay (#608 review).
  it "keeps frames from a different saboteur install" do
    foreign = dump.sub("#{tool_root}/lib/saboteur/engine/boot.rb",
                       "/vendored/gems/saboteur-0.8.0/lib/saboteur/engine/boot.rb")
    expect(filter(foreign)).to include("# /vendored/gems/saboteur-0.8.0/lib/saboteur/engine/boot.rb:74")
  end

  it "drops RSpec's contradictory 'No examples found.' line" do
    expect(filter(dump)).not_to include("No examples found.")
  end

  it "prints only the first error when several files failed to load, and says more exist" do
    second = dump.sub("./spec/thing_spec.rb.", "./spec/other_spec.rb.")
    report = filter(dump + second)
    expect(report).to include("thing_spec.rb")
    expect(report).not_to include("other_spec.rb")
    expect(report).to include("1 more load error")
    expect(report).to include("--verbose")
  end

  it "keeps the full dump, saboteur frames and all, under --verbose" do
    report = filter(dump, verbose: true)
    expect(report).to include("lib/saboteur/integration/rspec.rb")
    expect(report).to include("No examples found.")
  end

  describe "setup" do
    # A spec file calling exit at load: the captured RSpec output is
    # replayed (it names the file) before the tool error raises (#411/#608).
    it "replays the captured load output when a spec file exits at load" do
      integration = described_class.new(Saboteur::Config.new({}, root: Dir.pwd))
      runner = instance_double(RSpec::Core::Runner)
      allow(RSpec::Core::Runner).to receive(:new).and_return(runner)
      allow(runner).to receive(:setup) do |_err, out|
        out.write("While loading ./spec/boot_spec.rb an `exit` occurred\n")
        raise SystemExit, "exit called"
      end
      expect { integration.setup }
        .to raise_error(Saboteur::Error, /a spec file called exit while loading/)
        .and output(%r{While loading \./spec/boot_spec\.rb}).to_stdout
    end
  end

  describe "SetupOutputCapture" do
    it "buffers instead of passing through, and replays verbatim on demand" do
      io = StringIO.new
      capture = described_class::SetupOutputCapture.new(io)
      capture.write("one")
      capture.puts("two")
      expect(io.string).to eq("")
      capture.replay
      expect(io.string).to eq("onetwo\n")
    end
  end
end
