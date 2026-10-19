# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Execution::GemfilePathSources do
  def write_gemfile(dir, body)
    File.write(File.join(dir, "Gemfile"), body)
  end

  # The escaped grandchild is orphaned with the resolver, so it is not ours to
  # wait on; TERM by pid is the whole cleanup, and a subreaper reaps it.
  def reap_grandchild(pidfile)
    return unless File.exist?(pidfile)

    pid = File.read(pidfile).to_i
    Process.kill("TERM", pid) if pid.positive?
  rescue Errno::ESRCH
    nil
  end

  it "is empty without a Gemfile and never shells out" do
    Dir.mktmpdir do |dir|
      expect(described_class).not_to receive(:run_resolver)
      expect(described_class.resolve(dir)).to eq([])
    end
  end

  it "resolves path: sources with Bundler's own parser, not a line scan" do
    Dir.mktmpdir do |dir|
      [["../mygem", "mygem"], ["vendor/absgem", "absgem"]].each do |relative, name|
        root = File.expand_path(relative, dir)
        FileUtils.mkdir_p(File.join(root, "lib"))
        File.write(File.join(root, "#{name}.gemspec"),
                   "Gem::Specification.new { |s| s.name = \"#{name}\"; s.version = \"0.1.0\"; s.authors = [\"x\"]; " \
                   "s.summary = \"x\" }\n")
      end
      write_gemfile(dir, <<~RUBY)
        source "https://rubygems.org"
        gem "rails"
        gem "mygem", path: "../mygem"
        gem "absgem", path: "#{File.join(dir, 'vendor', 'absgem')}"
      RUBY

      sources = described_class.resolve(dir)
      by_name = sources.to_h { |src| [src.name, src] }
      expect(sources.map(&:name)).to contain_exactly("mygem", "absgem")
      expect(by_name["mygem"].original).to eq("../mygem")
      expect(by_name["mygem"].expanded).to eq(File.expand_path("../mygem", dir))
      expect(by_name["absgem"].expanded).to eq(File.join(dir, "vendor", "absgem"))
    end
  end

  it "fails closed when the Gemfile cannot be parsed" do
    Dir.mktmpdir do |dir|
      write_gemfile(dir, "gem 'unclosed\n")

      expect { described_class.resolve(dir) }
        .to raise_error(Saboteur::ConfigError, /could not parse the Gemfile's path: sources/)
    end
  end

  it "fails closed when the resolver output is unreadable" do
    Dir.mktmpdir do |dir|
      write_gemfile(dir, "source \"https://rubygems.org\"\n")
      status = instance_double(Process::Status, success?: true)
      allow(described_class).to receive(:run_resolver).and_return(["not json", "", status])

      expect { described_class.resolve(dir) }
        .to raise_error(Saboteur::ConfigError, /unreadable output/)
    end
  end

  it "resolves a gemspec's own path source at the project root" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "tool.gemspec"),
                 "Gem::Specification.new { |s| s.name = \"tool\"; s.version = \"0.1.0\"; s.authors = [\"x\"]; " \
                 "s.summary = \"x\" }\n")
      FileUtils.mkdir_p(File.join(dir, "vend", "inner"))
      write_gemfile(dir, "source \"https://rubygems.org\"\ngemspec\ngem \"inner\", path: \"vend/inner\"\n")

      by_name = described_class.resolve(dir).to_h { |src| [src.name, src] }
      expect(by_name.keys).to contain_exactly("tool", "inner")
      expect(by_name["tool"].original).to eq(".")
      expect(by_name["tool"].expanded).to eq(File.expand_path(dir))
      expect(by_name["inner"].expanded).to eq(File.join(dir, "vend", "inner"))
    end
  end

  it "parses a command-pinned BUNDLE_GEMFILE instead of the root Gemfile" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "gemfiles"))
      FileUtils.mkdir_p(File.join(dir, "vend", "inner"))
      write_gemfile(dir, "source \"https://rubygems.org\"\ngem \"rootgem\", path: \"vend/rootgem\"\n")
      File.write(File.join(dir, "gemfiles", "custom.gemfile"),
                 "source \"https://rubygems.org\"\ngem \"inner\", path: \"vend/inner\"\n")

      sources = described_class.resolve(dir, gemfile: "gemfiles/custom.gemfile")
      expect(sources.map(&:name)).to eq(["inner"])
    end
  end

  it "refuses a command-pinned BUNDLE_GEMFILE that does not exist, failing closed (#722)" do
    Dir.mktmpdir do |dir|
      write_gemfile(dir, "source \"https://rubygems.org\"\n")

      expect { described_class.resolve(dir, gemfile: "gemfiles/missing.gemfile") }
        .to raise_error(Saboteur::ConfigError, /does not exist/)
    end
  end

  it "drains a resolver child that writes more than a pipe buffer to stderr" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "vend", "inner"))
      write_gemfile(dir, <<~RUBY)
        source "https://rubygems.org"
        $stderr.write("x" * 200_000)
        gem "inner", path: "vend/inner"
      RUBY

      expect(described_class.resolve(dir, timeout: 10).map(&:name)).to eq(["inner"])
    end
  end

  it "falls back to expand_path when realpath races the path away (#722)" do
    Dir.mktmpdir do |dir|
      allow(File).to receive(:realpath).and_raise(Errno::ENOENT)
      expect(described_class.canonical_path(dir)).to eq(File.expand_path(dir))
    end
  end

  it "does not block on the pipes of a grandchild that left the process group (#722)" do
    Dir.mktmpdir do |dir|
      pidfile = File.join(dir, "grandchild.pid")
      write_gemfile(dir, "File.write(\"#{pidfile}\", spawn(RbConfig.ruby, \"-e\", \"Process.setsid; sleep 30\"))\n" \
                         "sleep 30\n")

      begin
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        expect { described_class.resolve(dir, timeout: 1) }
          .to raise_error(Saboteur::ConfigError, /timed out/)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        expect(elapsed).to be < 15
      ensure
        reap_grandchild(pidfile)
      end
    end
  end

  it "refuses a clean-exiting resolver whose grandchild holds the pipes open (#722)" do
    Dir.mktmpdir do |dir|
      pidfile = File.join(dir, "grandchild.pid")
      write_gemfile(dir, "File.write(\"#{pidfile}\", spawn(RbConfig.ruby, \"-e\", \"Process.setsid; sleep 25\"))\n")

      begin
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        expect { described_class.resolve(dir) }
          .to raise_error(Saboteur::ConfigError, /pipes open/)
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 15
      ensure
        reap_grandchild(pidfile)
      end
    end
  end

  it "kills the resolver's whole process group on timeout, not only the ruby pid" do
    Dir.mktmpdir do |dir|
      flag = File.join(dir, "grandchild-lived")
      write_gemfile(dir, <<~RUBY)
        spawn("sh", "-c", "sleep 2; touch #{flag}")
        sleep 30
      RUBY

      expect { described_class.resolve(dir, timeout: 1) }
        .to raise_error(Saboteur::ConfigError, /timed out/)
      sleep 3
      expect(File.exist?(flag)).to be(false)
    end
  end
end
