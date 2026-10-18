# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# Real confinement, exercised by the saboteur-mac runners and skipped
# elsewhere: a restricted child cannot write outside its grants.
RSpec.describe Saboteur::Execution::Seatbelt, "confinement (needs macOS Seatbelt)" do
  before { skip "Seatbelt unavailable" unless described_class.available? }

  it "blocks writes outside the grants and allows the granted dir" do
    Dir.mktmpdir do |dir|
      granted = File.join(dir, "granted")
      FileUtils.mkdir_p(granted)
      reader, writer = IO.pipe
      pid = fork do
        reader.close
        described_class.restrict!(writable: [granted], keep_fds: [writer.fileno])
        writer.write(JSON.generate(inside: writable?(File.join(granted, "ok.txt")),
                                   outside: writable?(File.join(dir, "nope.txt"))))
        writer.close
        exit!(0)
      end
      writer.close
      verdict = JSON.parse(reader.read, symbolize_names: true)
      Process.waitpid(pid)
      expect(verdict).to eq(inside: true, outside: false)
    end
  end

  def writable?(path)
    File.write(path, "x")
    true
  rescue SystemCallError
    false
  end
end
