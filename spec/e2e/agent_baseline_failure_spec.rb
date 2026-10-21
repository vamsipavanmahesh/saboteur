# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "agent mode when the baseline child dies", :e2e do
  let(:dir) { copy_fixture("people") }

  # The child's own rescue writes a failure payload for ordinary raises, so
  # the supervisor's labeled dying-child warning only runs when the raise
  # escapes that rescue too - here the hook exception's #message itself
  # raises, which is exactly the broken-reporting shape the warning exists
  # for. The label reaches the parent's stderr through the inline log
  # excerpt of the refused baseline check.
  it "emits one JSON failure doc and the labeled warning when the child raises past its rescue (#289)" do
    File.write(File.join(dir, "hooks.rb"), <<~RUBY)
      class BootBomb < StandardError
        def message = raise("boot exploded")
      end

      Saboteur.hook(:after_fork) { raise BootBomb }
    RUBY
    config = File.join(dir, "config", "saboteur.rb")
    File.write(config, <<~RUBY)
      Saboteur.configure do |c|
        c.include = ["lib/**/*.rb"]
        c.hooks = ["hooks.rb"]
      end
    RUBY

    run = saboteur(dir, "--all", "--agent")
    expect(run.status).to eq(5), run.err
    payload = JSON.parse(run.out) # raises unless stdout is exactly one JSON doc
    expect(payload).to include("status" => "error", "verdict" => "tool_failure", "exitCode" => 5)
    expect(run.err).to include("baseline check 1 failed at seed 1")
    expect(run.err).to include("baseline child died during setup/run: RuntimeError: boot exploded")
  end
end
