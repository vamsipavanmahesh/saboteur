# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"

# The seatbelt opt-in fails closed (#436): a probe verdict that is neither
# enforcement nor a clean absence refuses the run, and the refusal names
# what the probe said so the user is not sent debugging a green suite.
RSpec.describe Saboteur::Engine::SandboxPolicy, "seatbelt probe refusal (#436)" do
  around do |example|
    Dir.mktmpdir { |dir| @root = File.realpath(dir) and example.run }
  end

  let(:diagnostics) { Saboteur::Engine::Diagnostics.new(StringIO.new) }
  let(:policy) do
    described_class.new(config: Saboteur::Config.new({ "sandbox" => "seatbelt" }, root: @root),
                        root: @root, diagnostics: diagnostics)
  end

  it "names an unenforced-profile verdict in the refusal" do
    allow(Saboteur::Execution::Seatbelt).to receive(:probe).and_return(:unenforced)
    message = "the Seatbelt probe reported a profile that did not enforce - a macOS update may have changed it " \
              "(#436); refusing to run unsandboxed - set c.sandbox = true to run with the hazard guard and " \
              "canary only, or false to opt out"
    expect { policy.seatbelt_hook }.to raise_error(Saboteur::Error, Regexp.new(Regexp.escape(message)))
  end

  it "names an errored probe verdict in the refusal" do
    allow(Saboteur::Execution::Seatbelt).to receive(:probe).and_return("sandbox_init: -1")
    expect { policy.seatbelt_hook }.to raise_error(Saboteur::Error, /failed \(sandbox_init: -1\)/)
  end
end
