# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"
require "tmpdir"

# The state-machine specs stub Coverage; this one measures with the real
# thing in a subprocess: hits must stop while the guard holds the
# suspension and continue after resume (#254).
RSpec.describe Saboteur::Engine::CoverageGuard, "real Coverage hit counts" do
  it "stops counting while suspended and counts again after resume" do
    Dir.mktmpdir do |dir|
      target = File.join(dir, "target.rb")
      File.write(target, "class Target\n  def self.ping\n    1\n  end\nend\n")
      lib = File.expand_path("../../../lib", __dir__)
      script = <<~RUBY
        require "coverage"
        Coverage.start(lines: true)
        $LOAD_PATH.unshift(#{lib.inspect})
        require "saboteur/engine/coverage_guard"
        require #{target.inspect}
        Target.ping
        diagnostics = Object.new
        def diagnostics.warn(message) = nil
        guard = Saboteur::Engine::CoverageGuard.new(diagnostics)
        guard.suspend
        Target.ping
        guard.resume
        Target.ping
        puts Coverage.result.fetch(File.expand_path(#{target.inspect})).fetch(:lines)[2]
      RUBY
      out, err, status = Open3.capture3(RbConfig.ruby, "-e", script, chdir: dir)
      expect(status.exitstatus).to eq(0), err
      expect(out.strip).to eq("2") # three pings, the suspended one uncounted
    end
  end
end
