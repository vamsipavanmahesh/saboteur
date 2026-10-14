# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "support"

RSpec.describe Preflight::SafeOutput do
  let(:root) { File.realpath(Dir.mktmpdir("safe-root")) }
  let(:run) { File.join(root, "tmp", "run") }

  before { FileUtils.chmod(0o700, root) }
  after { FileUtils.remove_entry(root) }

  it "accepts a small clean tree (valid control)" do
    described_class.make_directories(File.join(run, "logs"), root)
    described_class.write_new(File.join(run, "logs", "a.log"), "x", root)
    expect { described_class.verify_tree(run, root) }.not_to raise_error
  end

  it "rejects a tree nested deeper than the limit" do
    deep = File.join(run, Array.new(6, "d"))
    described_class.make_directories(deep, root)
    expect { described_class.verify_tree(run, root, max_depth: 3) }
      .to raise_error(Preflight::ExecutionGap, /deeper than 3/)
  end

  it "rejects a tree with more entries than the limit" do
    described_class.make_directories(run, root)
    5.times { |i| described_class.write_new(File.join(run, "f#{i}"), "x", root) }
    expect { described_class.verify_tree(run, root, max_entries: 4) }
      .to raise_error(Preflight::ExecutionGap, /more than 4 entries/)
  end

  it "rejects a walk that takes longer than the time limit" do
    described_class.make_directories(run, root)
    described_class.write_new(File.join(run, "f"), "x", root)
    expect { described_class.verify_tree(run, root, max_seconds: -1) }
      .to raise_error(Preflight::ExecutionGap, /took longer/)
  end

  it "walks a deep tree without recursion (no stack overflow)" do
    deep = File.join(run, Array.new(12, "d"))
    described_class.make_directories(deep, root)
    expect { described_class.verify_tree(run, root, max_depth: 50) }.not_to raise_error
  end

  it "still rejects a symlink inside the tree" do
    described_class.make_directories(run, root)
    File.symlink("/etc", File.join(run, "link"))
    expect do
      described_class.verify_tree(run, root)
    end.to raise_error(Preflight::ExecutionGap, /not a directory or regular/)
  end

  it "rejects '..', '.' and empty components even when the path stays lexically below the root" do
    ["tmp/../../etc", "tmp/./x", "tmp//x"].each do |relative|
      expect { described_class.make_directories("#{root}/#{relative}", root) }
        .to raise_error(Preflight::ExecutionGap, /component/)
    end
    expect { described_class.write_new("#{root}/tmp/../escape.txt", "x", root) }
      .to raise_error(Preflight::ExecutionGap, /component/)
    expect(File.exist?(File.join(File.dirname(root), "escape.txt"))).to be(false)
  end
end
