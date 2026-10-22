# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"

# Review C1: a scoped (--since) run's own coverage map holds only the specs
# it loaded, so a survivor's "covered by" list used to read as complete when
# another spec pins the behavior - false survivors by default. Survivor
# presentation now consults the cached whole-suite map (built by a full
# `saboteur run`) and names covering specs the run never loaded. Selection
# itself stays on the run's own map.
RSpec.describe "survivor blocks consult the whole-suite coverage map", :e2e do
  let(:dir) { copy_fixture("people") }

  def git(*args)
    _out, err, status = Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
    raise err unless status.success?
  end

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
    File.write(File.join(dir, path), text)
  end

  before do
    write("lib/router.rb", <<~RUBY)
      class Router
        def route(path)
          "/api\#{path}"
        end
      end
    RUBY
    # Weak assertion: the line runs, but the spec passes without pinning the
    # prefix - the mutant survives a router-only run.
    write("spec/router_spec.rb", <<~RUBY)
      require_relative "../lib/router"

      RSpec.describe Router do
        it("keeps the path") { expect(described_class.new.route("/users")).to include("/users") }
      end
    RUBY
    # The spec outside the --since scope that actually pins the behavior:
    # inferred in a full run (flow.rb -> flow_spec.rb by name), not when only
    # router.rb changed.
    write("lib/flow.rb", <<~RUBY)
      require_relative "router"

      class Flow
        def self.entry(path) = Router.new.route(path)
      end
    RUBY
    write("spec/flow_spec.rb", <<~RUBY)
      require_relative "../lib/flow"

      RSpec.describe Flow do
        it("reaches the api") { expect(described_class.entry("/users")).to eq("/api/users") }
      end
    RUBY
    git("init", "-q")
    git("add", ".")
    git("commit", "-q", "-m", "base")
  end

  it "names the covering spec a --since run never loaded and marks the block" do
    full = saboteur(dir) # builds the whole-suite coverage map cache
    expect(full.json).not_to be_nil

    write("lib/router.rb", <<~RUBY)
      class Router
        def route(path)
          prefix = "/api"
          "\#{prefix}\#{path}"
        end
      end
    RUBY
    run = saboteur(dir, "--since", "HEAD")

    expect(run.status).to eq(1), run.out + run.err
    expect(run.out).to include("covered by 2 specs, incl. ./spec/flow_spec.rb[1:1] (not run here)")
    expect(run.out).to include("likely covered elsewhere: ./spec/flow_spec.rb[1:1] pins this line (not run here)")
  end
end
