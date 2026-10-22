# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::CLI::RunCommand do
  def cli(*argv) = Saboteur::CLI.new(["run", *argv], out: StringIO.new, err: err)

  let(:err) { StringIO.new }

  it "is mixed into Saboteur::CLI like the other extracted commands (#334)" do
    expect(Saboteur::CLI.ancestors).to include(described_class)
  end

  it "owns the run command, moved out of CLI itself" do
    owned = %i[run_command run]
    expect(described_class.private_instance_methods(false)).to include(*owned)
    expect(Saboteur::CLI.private_instance_methods(false)).not_to include(*owned)
  end

  %w[--help -h].each do |flag|
    it "shows exactly the run help for #{flag} instead of running" do
      out = StringIO.new
      run = Saboteur::CLI.new(["run", flag], out:, err:)
      expected = Saboteur::Help.new(option_lines: run.send(:option_lines)).command("run")
      code = begin
        run.call
      rescue SystemExit
        flunk "the option parser took #{flag} and exited instead of showing the run help"
      end
      expect(code).to eq(0)
      expect(out.string).to eq("#{expected.chomp}\n")
    end
  end

  it "exits 2 and names a configuration error" do
    Dir.mktmpdir do |dir|
      config = File.join(dir, "saboteur.rb")
      File.write(config, "Saboteur.configure { |c| c.jobs = 0 }")
      code = cli("--config", config).call
      expect(code).to eq(2)
      expect(err.string).to start_with("saboteur: ")
    end
  end

  it "exits 3 and names a tool error raised while the run executes" do
    run = cli("--all")
    allow(run).to receive(:refuse_empty_source_set)
    allow(run).to receive(:execute_run).and_raise(Saboteur::Error, "boom")
    expect(run.call).to eq(3)
    expect(err.string).to end_with("saboteur: boom\n")
  end

  it "says once when no config file exists and defaults are in use (#1172)" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        run = cli("--all")
        allow(run).to receive(:refuse_empty_source_set)
        allow(run).to receive(:execute_run).and_raise(Saboteur::Error, "stop")
        run.call
        expect(err.string).to include("saboteur: no config/saboteur.rb - using defaults " \
                                      "(Rails: bundle exec rails generate saboteur:install writes one)")
      end
    end
  end

  it "announces the Rails app/** default when no config file exists on a Rails app (#1171)" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "application.rb"), "module Demo; end\n")
      FileUtils.mkdir_p(File.join(dir, "app", "models"))
      File.write(File.join(dir, "app", "models", "user.rb"), "class User; end\n")
      Dir.chdir(dir) do
        run = cli("--all")
        allow(run).to receive(:execute_run).and_raise(Saboteur::Error, "stop")
        run.call
        expect(err.string).to include("saboteur: no config/saboteur.rb - Rails app detected, " \
                                      "mutating app/**/*.rb " \
                                      "(bundle exec rails generate saboteur:install writes a config)")
      end
    end
  end

  it "keeps the plain notice when app/** was named explicitly, not detected (#1171)" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "application.rb"), "module Demo; end\n")
      FileUtils.mkdir_p(File.join(dir, "app", "models"))
      File.write(File.join(dir, "app", "models", "user.rb"), "class User; end\n")
      Dir.chdir(dir) do
        run = cli("--all", "app")
        allow(run).to receive(:execute_run).and_raise(Saboteur::Error, "stop")
        run.call
        expect(err.string).to include("using defaults")
        expect(err.string).not_to include("Rails app detected")
      end
    end
  end

  it "names a custom --config path in the missing-config notice (#1172)" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        run = cli("--all", "--config", "config/custom.rb")
        allow(run).to receive(:refuse_empty_source_set)
        allow(run).to receive(:execute_run).and_raise(Saboteur::Error, "stop")
        run.call
        expect(err.string).to include("saboteur: no config/custom.rb - using defaults " \
                                      "(Rails: bundle exec rails generate saboteur:install writes one)")
      end
    end
  end

  it "prints the missing-config notice for an explicit non-agent format (#1172)" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        run = cli("--all", "--format", "text")
        allow(run).to receive(:refuse_empty_source_set)
        allow(run).to receive(:execute_run).and_raise(Saboteur::Error, "stop")
        run.call
        expect(err.string).to include("using defaults")
      end
    end
  end

  it "keeps the missing-config line out of agent output (#1172)" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        run = cli("--all", "--format", "agent")
        allow(run).to receive(:refuse_empty_source_set)
        allow(run).to receive(:execute_run).and_raise(Saboteur::Error, "stop")
        run.call
        expect(err.string).not_to include("using defaults")
      end
    end
  end

  it "stays silent about the config file when one exists (#1172)" do
    run = cli("--all")
    allow(run).to receive(:refuse_empty_source_set)
    allow(run).to receive(:execute_run).and_raise(Saboteur::Error, "stop")
    run.call
    expect(err.string).not_to include("using defaults")
  end

  it "prints each deprecation warning once, behind the saboteur prefix" do
    run = cli("--no-guess-tests")
    allow(run).to receive(:execute_run).and_raise(Saboteur::Error, "stop")
    allow(run).to receive(:refuse_empty_source_set)
    run.call
    expect(err.string.lines.grep(/deprecated/)).to match([/\Asaboteur: guess_tests = false is deprecated: /])
  end

  it "paints deprecation warnings with the warn token when colour is on" do
    run = cli("--no-guess-tests", "--color=always")
    allow(run).to receive(:execute_run).and_raise(Saboteur::Error, "stop")
    allow(run).to receive(:refuse_empty_source_set)
    run.call
    expect(err.string).to include("\e[33msaboteur: guess_tests = false is deprecated:")
  end

  it "honours the config palette override for deprecation warnings" do
    config = instance_double(Saboteur::Config, deprecation_warnings: ["old key is deprecated"],
                                               config_file_present: true)
    allow(config).to receive(:[]).and_return(nil)
    allow(config).to receive(:[]).with("palette").and_return({ "warn" => ["red"] })
    run = cli("--all", "--color=always")
    allow(run).to receive(:warn_dirty_tree)
    allow(run).to receive(:config).and_return(config)
    allow(run).to receive(:execute_run).and_raise(Saboteur::Error, "stop")
    allow(run).to receive(:refuse_empty_source_set)
    run.call
    expect(err.string).to include("\e[31msaboteur: old key is deprecated\e[0m")
  end
end
