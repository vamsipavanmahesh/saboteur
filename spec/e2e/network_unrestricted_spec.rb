# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Models the README "Know the limits" statement "network access is never
# restricted": a spec that does a loopback TCP round-trip passes inside
# mutant children, so a run over it scores normally. (Documents current
# behavior; restricting the network would turn this red.)
RSpec.describe "network use inside a mutant child (end to end)", :e2e do
  it "lets the suite use loopback TCP and still scores the run" do
    dir = copy_fixture("people")
    File.write(File.join(dir, "lib", "echo.rb"), <<~RUBY)
      require "socket"

      module Echo
        def self.round_trip(message)
          server = TCPServer.new("127.0.0.1", 0)
          port = server.addr[1]
          thread = Thread.new { server.accept.tap { |client| client.write(client.gets) }.close }
          TCPSocket.open("127.0.0.1", port) do |socket|
            socket.puts(message)
            socket.gets
          end
        ensure
          thread&.join
          server&.close
        end
      end
    RUBY
    File.write(File.join(dir, "spec", "echo_spec.rb"), <<~RUBY)
      require_relative "../lib/echo"

      RSpec.describe Echo do
        it "answers over loopback TCP" do
          expect(described_class.round_trip("ping")).to include("ping")
        end
      end
    RUBY
    run = saboteur(dir, "--subject", "Echo.round_trip")
    expect(run.status).to eq(1), run.err # survivors: the mutant differs, the suite stays green
    expect(run.out).to include("Score:")
    expect(run.out).not_to include("Errno::EACCES", "Errno::EPERM", "Errno::EADDRNOTAVAIL")
  end
end
