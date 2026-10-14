# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "timeout"
require "open3"
require "json"
require "fileutils"
require_relative "../../../script/preflight_support/preflight"

# Temporary git repositories and a scripted command runner for the preflight specs.
module PreflightSupport
  FIXTURE_DIRECTORY = File.expand_path("fixtures", __dir__)

  def self.fixture_text(name)
    File.read(File.join(FIXTURE_DIRECTORY, name))
  end

  def self.fixture_json(name)
    JSON.parse(fixture_text(name))
  end

  POLICY = { "schema" => 1, "protectedFiles" => [".github/workflows", "script/check-dco", "integration"] }.freeze

  class Fixture
    attr_reader :directory

    def initialize
      @directory = Dir.mktmpdir("preflight-fixture")
      git("init", "-q", "-b", "main")
      git("config", "user.name", "Fixture Author")
      git("config", "user.email", "author@example.test")
      write("script/panel-gate/policy.json", JSON.generate(POLICY))
      write("README.md", "base\n")
      commit("base")
    end

    def cleanup
      FileUtils.remove_entry(@directory)
    end

    def git(*arguments)
      output, status = Open3.capture2e("git", *arguments, chdir: @directory)
      raise "git #{arguments.join(' ')} failed: #{output}" unless status.success?

      output
    end

    def write(path, content)
      full = File.join(@directory, path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
    end

    def commit(message, signoff: "Fixture Author <author@example.test>")
      git("add", "-A")
      body = signoff ? "#{message}\n\nSigned-off-by: #{signoff}" : message
      git("commit", "-q", "--allow-empty", "-m", body)
      head
    end

    def head
      git("rev-parse", "HEAD").strip
    end

    def options(base:, mode: "full")
      Preflight::Options.new(base: base, head: head, base_ref: "main", mode: mode)
    end

    def runner(**settings)
      Preflight::CommandRunner.new(directory: @directory, **settings)
    end

    def repository(base:, mode: "full", runner: self.runner)
      Preflight::Repository.new(command_runner: runner, options: options(base: base, mode: mode),
                                directory: @directory).tap(&:verify_identity!)
    end
  end

  # Replays canned results by the first matching argv prefix; records every call.
  class ScriptedRunner
    attr_reader :calls

    def initialize(&responder)
      @responder = responder
      @calls = []
    end

    def data_shim_path
      "/harness/rspec_fd3_shim.rb"
    end

    def run(argv, **_options)
      @calls << argv
      @responder.call(argv) || result(argv, 0, "")
    end

    def result(argv, status, stdout, stderr: "", **flags)
      Preflight::CommandResult.new(argv: argv, directory: ".", exit_status: status, stdout: stdout, stderr: stderr,
                                   timed_out: false, truncated: false, **flags)
    end
  end
end

RSpec.configure do |config|
  config.around(:each, :fixture) do |example|
    @fixture = PreflightSupport::Fixture.new
    @base = @fixture.head
    example.run
  ensure
    @fixture&.cleanup
  end
end
