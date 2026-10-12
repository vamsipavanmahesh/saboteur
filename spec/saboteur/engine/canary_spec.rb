# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Saboteur::Engine::Canary do
  def in_tmpdir
    Dir.mktmpdir("saboteur-canary-") { |dir| yield File.realpath(dir) }
  end

  it "passes when nothing vanished" do
    in_tmpdir do |dir|
      File.write(File.join(dir, "a.rb"), "x")
      canary = described_class.new(dir)
      expect { canary.check! }.not_to raise_error
    end
  end

  it "raises CanaryTripped naming the digest when a file vanishes" do
    in_tmpdir do |dir|
      File.write(File.join(dir, "a.rb"), "x")
      File.write(File.join(dir, "b.rb"), "y")
      canary = described_class.new(dir)
      File.delete(File.join(dir, "a.rb"))
      expect { canary.check!(digest: "0123456789abcdef") }
        .to raise_error(Saboteur::CanaryTripped, /1 file.*a\.rb.*0123456789abcdef/m)
    end
  end

  it "ignores changes inside the cache directory" do
    in_tmpdir do |dir|
      File.write(File.join(dir, "a.rb"), "x")
      FileUtils.mkdir_p(File.join(dir, ".saboteur"))
      File.write(File.join(dir, ".saboteur", "report.json"), "{}")
      canary = described_class.new(dir, cache_dir: ".saboteur")
      File.delete(File.join(dir, ".saboteur", "report.json"))
      expect { canary.check! }.not_to raise_error
    end
  end

  it "watches .git presence in a repository" do
    in_tmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".git"))
      File.write(File.join(dir, ".git", "HEAD"), "ref: refs/heads/main")
      File.write(File.join(dir, "a.rb"), "x")
      canary = described_class.new(dir)
      FileUtils.rm_rf(File.join(dir, ".git"))
      expect { canary.check! }.to raise_error(Saboteur::CanaryTripped, /\.git/)
    end
  end

  it "names the subject in the message when given one" do
    in_tmpdir do |dir|
      File.write(File.join(dir, "a.rb"), "x")
      canary = described_class.new(dir)
      File.delete(File.join(dir, "a.rb"))
      subject = instance_double(Saboteur::Subject, id: "K#m")
      expect { canary.check!(subject: subject, digest: "0123456789abcdef") }
        .to raise_error(Saboteur::CanaryTripped, /0123456789abcdef of K#m/)
    end
  end

  it "names no culprit when no digest is known" do
    in_tmpdir do |dir|
      File.write(File.join(dir, "a.rb"), "x")
      canary = described_class.new(dir)
      File.delete(File.join(dir, "a.rb"))
      expect { canary.check! }.to raise_error(Saboteur::CanaryTripped) do |error|
        expect(error.message).not_to include("most recent mutant")
      end
    end
  end

  it "watches files in nested directories" do
    in_tmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "sub"))
      File.write(File.join(dir, "sub", "b.rb"), "y")
      canary = described_class.new(dir)
      File.delete(File.join(dir, "sub", "b.rb"))
      expect { canary.check! }.to raise_error(Saboteur::CanaryTripped, %r{sub/b\.rb})
    end
  end

  it "leaves untracked files alone inside a git repository" do
    in_tmpdir do |dir|
      system("git", "-C", dir, "init", "-q") or raise "git init failed"
      File.write(File.join(dir, "tracked.rb"), "x")
      system("git", "-C", dir, "add", "tracked.rb") or raise "git add failed"
      File.write(File.join(dir, "untracked.rb"), "y")
      canary = described_class.new(dir)
      File.delete(File.join(dir, "untracked.rb"))
      expect { canary.check! }.not_to raise_error
      File.delete(File.join(dir, "tracked.rb"))
      expect { canary.check! }.to raise_error(Saboteur::CanaryTripped, /tracked\.rb/)
    end
  end

  it "walks the tree when git ls-files fails" do
    in_tmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".git"))
      File.write(File.join(dir, "untracked.rb"), "y")
      status = instance_double(Process::Status, success?: false)
      allow(Open3).to receive(:capture2).and_return(["", status])
      canary = described_class.new(dir)
      File.delete(File.join(dir, "untracked.rb"))
      expect { canary.check! }.to raise_error(Saboteur::CanaryTripped, /untracked\.rb/)
    end
  end

  it "ignores the contents of a .git directory while walking" do
    in_tmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".git"))
      File.write(File.join(dir, ".git", "HEAD"), "ref: refs/heads/main")
      File.write(File.join(dir, "a.rb"), "x")
      allow(described_class).to receive(:new).and_call_original
      canary = described_class.allocate
      allow(canary).to receive(:system).and_return(false)
      canary.send(:initialize, dir)
      File.delete(File.join(dir, ".git", "HEAD"))
      expect { canary.check! }.not_to raise_error
    end
  end
end
