# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

# Drives script/rspec-shard in a throwaway git repo with fake spec files, a
# stub `bundle` that prints its arguments (so no real rspec run happens) and
# a silent stub environment gate (these examples test shard selection, not
# the gate; bin/check-env has its own specs under spec/bin).
RSpec.describe "script/rspec-shard" do
  let(:source) { File.expand_path("../../script/rspec-shard", __dir__) }
  let(:repo) { Dir.mktmpdir("rspec-shard") }
  let(:files) { (1..11).map { |n| format("spec/group%<n>d/thing%<n>d_spec.rb", n: n) } }

  after { FileUtils.remove_entry(repo) }

  # Other specs may leave GIT_* variables behind; the fixture repo must not see them.
  def clean_env(extra = {})
    ENV.keys.grep(/\AGIT_/).to_h { |key| [key, nil] }.merge(extra)
  end

  def git(*args)
    out, err, status = Open3.capture3(clean_env, "git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args,
                                      chdir: repo)
    raise "git #{args.join(' ')} failed: #{err}#{out}" unless status.success?
  end

  def write_file(path, content = "", mode: nil)
    full = File.join(repo, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
    FileUtils.chmod(mode, full) if mode
  end

  def build_repo(weights: nil, spec_files: files)
    write_file("script/rspec-shard", File.read(source), mode: 0o755)
    write_file("script/rspec-shard-weights.txt", weights) if weights
    # The script fail-fasts through the gate next to its repository root;
    # the fixture stubs it silent-green so the examples exercise sharding.
    write_file("bin/check-env", "exit 0\n", mode: 0o755)
    write_file("bin/bundle", "#!/usr/bin/env bash\nprintf '%s\\n' \"$@\"\n", mode: 0o755)
    (spec_files + ["spec/fixtures/app/skipped_spec.rb"]).each { |file| write_file(file) }
    git("init", "-q")
    git("add", "-A")
    git("commit", "-q", "-m", "base")
  end

  # [header line, files picked, extra args seen by the stubbed bundle exec rspec]
  def shard(index, total, *extra)
    out, err, status = Open3.capture3(clean_env("PATH" => "#{repo}/bin:#{ENV.fetch('PATH')}"),
                                      File.join(repo, "script", "rspec-shard"), index.to_s, total.to_s, *extra,
                                      chdir: repo)
    expect(status).to be_success, "#{err}#{out}"
    lines = out.lines(chomp: true)
    header = lines.shift
    expect(lines.shift(2)).to eq(%w[exec rspec])
    passed = lines.shift(extra.size)
    [header, lines, passed]
  end

  # Today's deal: sorted position i goes to shard i % total.
  def round_robin(total)
    files.sort.each_with_index.group_by { |_, i| i % total }.sort.map { |_, pairs| pairs.map(&:first) }
  end

  def picked_by_shard(total) = (1..total).map { |index| shard(index, total)[1] }

  def weighted(pairs) = pairs.map { |path, seconds| "#{seconds} #{path}\n" }.join

  def all_weights(files) = weighted(files.each_with_index.map { |file, i| [file, (i + 1) * 1.5] })

  def weights_for(name)
    case name
    when :none then nil
    when :comments then "# nothing yet\n\n"
    when :all then all_weights(files)
    when :some then weighted(files.first(4).zip([40, 3, 17.5, 9]))
    when :messy
      ["# header", "", weighted(files.first(3).zip([30, 20, 10])), "99 spec/gone/removed_spec.rb",
       "not a weight", "0 #{files[4]}"].join("\n")
    end
  end

  [1, 3, 5].each do |total|
    context "with TOTAL #{total}" do
      { none: "no weights file", comments: "a comments-only weights file", all: "weights for every file",
        some: "weights for some files", messy: "stale paths, comments and blank lines" }.each do |name, label|
        it "puts every spec file in exactly one shard, with #{label}" do
          build_repo(weights: weights_for(name))
          picked = picked_by_shard(total)

          expect(picked.flatten.sort).to eq(files.sort)
          expect(picked.flatten.size).to eq(files.size)
          expect(picked.flatten).not_to include("spec/fixtures/app/skipped_spec.rb")
        end
      end
    end
  end

  it "prints the shard line and passes extra rspec args through before the files" do
    build_repo
    header, picked, flags = shard(2, 3, "--tag", "focus")

    expect(header).to eq("shard 2/3: #{picked.size} of #{files.size} spec files")
    expect(flags).to eq(%w[--tag focus])
    expect(picked).to all(end_with("_spec.rb"))
  end

  it "reproduces today's round-robin when there is no weights file" do
    build_repo

    expect(picked_by_shard(3)).to eq(round_robin(3))
  end

  # `printf | head -n 1` under pipefail killed the script with SIGPIPE (exit
  # 141) when head closed the pipe before printf finished writing; a list
  # bigger than a pipe buffer makes that certain instead of a rare race.
  it "deals a spec list larger than a pipe buffer" do
    many = (1..2500).map { |n| format("spec/%<n>04d/#{'x' * 40}_spec.rb", n: n) }
    build_repo(spec_files: many)
    header, picked, = shard(1, 1)

    expect([header, picked]).to eq(["shard 1/1: #{many.size} of #{many.size} spec files", many.sort])
  end

  it "reproduces round-robin for an empty weights file too" do
    build_repo(weights: "")

    expect(picked_by_shard(5)).to eq(round_robin(5))
  end

  it "balances weighted files: the heaviest shard is at most the lightest plus the largest weight" do
    pairs = files.each_with_index.map { |file, i| [file, [60, 45, 30, 22, 15, 9, 7, 5, 3, 2, 1][i]] }
    build_repo(weights: weighted(pairs))
    weight = pairs.to_h
    [3, 5].each do |total|
      sums = picked_by_shard(total).map { |shard_files| shard_files.sum { |file| weight.fetch(file) } }

      expect(sums.max).to be <= sums.min + weight.values.max
    end
  end

  it "deals the heaviest file first and puts each next file on the lightest shard" do
    pairs = [[files[0], 10], [files[1], 7], [files[2], 6], [files[3], 5]]
    build_repo(weights: weighted(pairs), spec_files: files.first(4))

    expect(picked_by_shard(2)).to eq([[files[0], files[3]], [files[1], files[2]]].map(&:sort))
  end

  it "breaks weight ties by path and shard ties by the lowest index" do
    build_repo(weights: weighted(files.first(4).map { |file| [file, 5] }), spec_files: files.first(4))

    expect(picked_by_shard(2)).to eq([files.first(4).sort.values_at(0, 2), files.first(4).sort.values_at(1, 3)])
  end

  it "spreads unweighted files round-robin from the lightest shard, charging the median weight" do
    # weighted: one heavy file; the other 3 are unweighted and median is 8 (a single weight).
    # shard 1 gets the heavy file (8), so unweighted start at shard 2: s2, s1, s2.
    pairs = [[files[0], 8]]
    build_repo(weights: weighted(pairs), spec_files: files.first(4))
    unweighted = files.first(4).sort - [files[0]]
    expected = [[files[0], unweighted[1]], [unweighted[0], unweighted[2]]].map(&:sort)

    expect(picked_by_shard(2)).to eq(expected)
  end

  it "gives the same result on every run" do
    build_repo(weights: all_weights(files.first(6)))

    expect(picked_by_shard(3)).to eq(picked_by_shard(3))
  end

  it "stops before sharding when the environment gate is red" do
    build_repo
    write_file("bin/check-env", "warn \"check-env: FAIL stub gate\"\nexit 1\n", mode: 0o755)

    out, err, status = Open3.capture3(clean_env("PATH" => "#{repo}/bin:#{ENV.fetch('PATH')}"),
                                      File.join(repo, "script", "rspec-shard"), "1", "3", chdir: repo)

    expect(status).not_to be_success
    expect(err).to include("check-env: FAIL stub gate")
    expect(out).not_to include("shard 1/3")
  end

  it "lets a later weights line win for the same path" do
    build_repo(weights: weighted([[files[0], 1], [files[0], 90], [files[1], 40]]), spec_files: files.first(3))

    expect(picked_by_shard(2)[0]).to include(files[0])
  end
end
