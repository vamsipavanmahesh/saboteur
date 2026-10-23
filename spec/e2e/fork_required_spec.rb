# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Models the README "Know the limits" statement "it needs `fork`": with
# Kernel#fork made to raise NotImplementedError - the exact error CRuby
# raises on platforms without fork (CRuby defines fork as
# rb_f_notimplement when the platform lacks it: ruby/ruby process.c,
# https://github.com/ruby/ruby/blob/master/process.c) - a run cannot
# happen. This pins the fork dependence only: it does not promise a
# graceful error, and Windows itself is not exercised here (development
# and CI run on Linux); "no Windows" in the README follows from CRuby on
# Windows having no fork, not from a Windows test run.
RSpec.describe "a platform without fork (end to end)", :e2e do
  it "cannot run mutants when fork is unavailable" do
    dir = copy_fixture("people")
    stub = File.join(dir, "no_fork.rb")
    File.write(stub, <<~RUBY)
      module Kernel
        def fork(*)
          raise NotImplementedError, "fork() function is unimplemented on this machine"
        end
        module_function :fork
      end
    RUBY
    run = saboteur(dir, env: { "RUBYOPT" => "-r#{stub}" })
    expect(run.status).not_to eq(0)
    expect(run.err).to include("NotImplementedError")
  end
end
