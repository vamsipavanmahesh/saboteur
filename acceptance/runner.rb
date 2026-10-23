#!/usr/bin/env ruby
# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Black-box acceptance runner: builds the gem from source, installs it into an
# isolated GEM_HOME with rspec, and runs the real `saboteur` executable on
# fixture projects the way a user would, comparing results with
# acceptance/expected.yml. Prints PASS/FAIL per scenario case and exits 1 when
# any case fails.
#
# The runner never edits the repo, the fixtures, or expected.yml; fixture
# projects are copied to a temp dir before any saboteur run touches them.

require "fileutils"
require "rbconfig"
require "json"
require "open3"
require "open-uri"
require "shellwords"
require "tmpdir"
require "yaml"

class AcceptanceRunner
  ROOT = File.expand_path("..", __dir__)
  EXPECTED = File.join(ROOT, "acceptance", "expected.yml")
  FIXTURES = File.join(ROOT, "acceptance", "fixtures")
  COMMAND_TIMEOUT = 900

  RANK_LINE = /^\s*(\d+)\.\s+(\S+):(\d+)\s+\S+\s+[0-9a-f]{16}\s+(\S+)/

  RunResult = Struct.new(:out, :status, :json, keyword_init: true) do
    def text = out.to_s
  end

  def initialize(out: $stdout, keep: false)
    @out = out
    @keep = keep
    @failures = 0
    @cases = 0
  end

  def run
    check_environment!
    scenarios = YAML.load_file(EXPECTED).fetch("scenarios")
    Dir.mktmpdir("saboteur-acceptance-") do |work|
      gem_home = build_and_install_gem(work)
      only = ENV["ACCEPTANCE_ONLY"]&.split(",")
      fast = ENV["ACCEPTANCE_TIER"] == "fast"
      scenarios.each do |name, spec|
        next if only && !only.include?(name.to_s)
        next if fast && spec["tier"] == "full"

        run_scenario(name, spec, gem_home, work)
      end
    end
    print_summary
    @failures.zero? ? 0 : 1
  end

  private

  # Fail fast on an unfaithful toolchain (AGENTS.md, "Run discipline"): the
  # runner is also invoked directly (release gate, local runs), not only
  # through the rake tasks that already depend on the check_env task.
  def check_environment!
    return if system(RbConfig.ruby, File.join(ROOT, "bin", "check-env"), chdir: ROOT)

    @out.puts "acceptance: environment gate failed; refusing to run"
    exit 1
  end

  def build_and_install_gem(work)
    gem_home = File.join(work, "gemhome")
    FileUtils.mkdir_p(gem_home)
    gem_bin = File.join(RbConfig::CONFIG["bindir"], "gem")
    Dir.chdir(ROOT) do
      out, status = Open3.capture2e(Gem.ruby, gem_bin, "build", "saboteur.gemspec", "--output",
                                    File.join(work, "saboteur.gem"))
      abort "gem build failed:\n#{out}" unless status.success?
    end
    out, status = Open3.capture2e(Gem.ruby, gem_bin, "install", "--install-dir", gem_home, "--no-document",
                                  File.join(work, "saboteur.gem"), "rspec", "i18n")
    abort "gem install failed:\n#{out}" unless status.success?
    Dir.glob(File.join(gem_home, "bin", "*")).each do |bin|
      lines = File.readlines(bin)
      next unless lines.first&.start_with?("#!")

      lines[0] = "#!#{Gem.ruby}\n"
      File.write(bin, lines.join)
      FileUtils.chmod(0o755, bin)
    end
    @out.puts "acceptance: built and installed the gem from source into an isolated GEM_HOME"
    gem_home
  end

  def run_scenario(name, spec, gem_home, work)
    started = Time.now
    @out.puts "\n== #{name}"
    @out.puts spec["description"].to_s.strip.gsub(/^/, "   maintainer: ")
    begin
      dir = prepare_project(name, spec, work)
      spec.fetch("cases").each { |c| run_case(name, c, dir, gem_home) }
    rescue StandardError => e
      @failures += 1
      @out.puts "    ERROR: #{e.class}: #{e.message.lines.first}"
    end
  ensure
    @out.puts "   (#{(Time.now - started).round(1)}s)"
    FileUtils.rm_rf(dir) if dir && !@keep
  end

  def prepare_project(name, spec, work)
    dir = File.join(work, "project-#{name}")
    fixture = File.join(FIXTURES, spec.fetch("fixture"))
    if (source = spec["source"])
      fetch_remote(source.fetch("repo"), source.fetch("commit"), dir)
    else
      FileUtils.mkdir_p(dir)
    end
    Dir.glob(File.join(fixture, "**", "*"), File::FNM_DOTMATCH).each do |path|
      next if File.directory?(path) || File.basename(path) == "branch.diff"

      target = File.join(dir, path.delete_prefix("#{fixture}/"))
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(path, target)
    end
    git(dir, "init", "-q", "-b", "main")
    git(dir, "add", "-A")
    git(dir, "-c", "user.email=acceptance@saboteur.local", "-c", "user.name=acceptance", "commit", "-qm", "main")
    diff = File.join(fixture, "branch.diff")
    if File.file?(diff)
      git(dir, "checkout", "-qb", "change")
      git(dir, "apply", diff)
      git(dir, "-c", "user.email=acceptance@saboteur.local", "-c", "user.name=acceptance", "commit", "-qam", "change")
      git(dir, "checkout", "-q", "main")
    end
    dir
  end

  # A pinned commit is verified by git's own object identity: after checkout,
  # HEAD must equal the pin. A bare clone in tmp is the cache.
  def fetch_remote(repo, commit, dir)
    cache = File.join(Dir.tmpdir, "saboteur-acceptance-#{commit}.git")
    system("git", "clone", "--quiet", "--bare", repo, cache, exception: true) unless File.directory?(cache)
    system("git", "clone", "--quiet", cache, dir, exception: true)
    git(dir, "-c", "advice.detachedHead=false", "checkout", "-q", commit)
    out, status = Open3.capture2e("git", "-C", dir, "rev-parse", "HEAD")
    actual = status.success? ? out.strip : "rev-parse failed: #{out}"
    raise "remote fixture integrity: HEAD is #{actual}, expected pin #{commit}" unless actual == commit
  end

  def run_case(_scenario, kase, dir, gem_home)
    @cases += 1
    @out.puts " -- #{kase.fetch('name')}"
    @out.puts "    expects: #{kase['expect_description']}"
    problems = []
    results = []
    kase.fetch("steps").each do |step|
      step_problems, results = run_step(step, results, dir, gem_home)
      problems.concat(step_problems)
    end
    print_case_result(problems, results)
  end

  def run_step(step, results, dir, gem_home)
    if step["checkout"]
      git(dir, "checkout", "-q", step.fetch("checkout"))
      return [[], results]
    end
    if step["reset_state"]
      FileUtils.rm_rf(File.join(dir, ".saboteur"))
      return [[], results]
    end
    return [[], results] unless step["run"]

    results = Array.new(step["repeat"] || 1) { run_command(step.fetch("run"), dir, gem_home) }
    debug_run(step, results)
    problems = step["expect"] ? check_expectations(step.fetch("expect"), results, dir) : []
    [problems, results]
  end

  def debug_run(step, results)
    return unless ENV["ACCEPTANCE_DEBUG"]

    @out.puts "    [debug] #{step.fetch('run')}: exit #{results.last.status}"
    @out.puts results.last.text.lines.last(8).map { |line| "    [debug] | #{line}" }.join
  end

  def print_case_result(problems, results)
    if problems.empty?
      @out.puts "    PASS"
      return
    end

    @failures += 1
    problems.each { |problem| @out.puts "    FAIL: #{problem}" }
    return unless (last = results.last) && !last.text.empty?

    @out.puts "    --- last command output (tail) ---"
    @out.puts last.text.lines.last(15).map { |line| "    | #{line}" }.join
  end

  def run_command(command, dir, gem_home)
    env = clean_env(gem_home, dir)
    report = File.join(dir, ".saboteur", "report.json")
    # Clear a stale report before a mutation run so its JSON is attributable
    # to this step; read-only commands such as `survivors` consume it.
    FileUtils.rm_f(report) if command.start_with?("run ")
    out = nil
    status = nil
    Dir.chdir(dir) do
      out, status = Open3.capture2e(env, File.join(gem_home, "bin", "saboteur"), *Shellwords.split(command))
      # The subprocess writes UTF-8; the pipe inherits the runner's locale.
      out.force_encoding(Encoding::UTF_8)
    end
    json = File.file?(report) ? JSON.parse(File.read(report, encoding: "UTF-8")) : nil
    RunResult.new(out:, status: status.exitstatus, json:)
  end

  # The CLI runs the way a user's would: the built gem's own GEM_HOME, no
  # Bundler variables from the repository's own development environment.
  def clean_env(gem_home, dir)
    # spawn treats an absent key as "inherit": bundler variables must be
    # explicitly unset (nil), not merely omitted from the hash.
    env = ENV.to_h
    env.keys.each { |key| env[key] = nil if key.start_with?("BUNDLE_", "BUNDLER_", "RUBYOPT") }
    env["GEM_HOME"] = gem_home
    env["GEM_PATH"] = ([gem_home] + Gem.default_path).uniq.join(File::PATH_SEPARATOR)
    env["PATH"] = "#{File.join(gem_home, 'bin')}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}"
    # Keep the child's RUBYLIB minimal: just the project's lib (remote
    # fixtures such as money need it on the load path). RUBYLIB entries
    # shadow gem activation, so adding the running Ruby's stdlib dirs makes
    # a stock Ruby's bundled prism (3.3 ships 0.19 in rubylibdir) win over
    # the 1.x the gemspec requires - CI run 39928487173 died 8/8 with a
    # Prism::ParseResult superclass mismatch (exit 70). Only Ruby builds
    # that cannot load rubygems without RUBYLIB (relocated, non-default
    # prefix) keep their stdlib dirs, as the last entries.
    rubylib = [File.join(dir, "lib")]
    rubylib += [RbConfig::CONFIG["rubylibdir"], RbConfig::CONFIG["archdir"]] if ruby_needs_stdlib_dirs?
    env["RUBYLIB"] = rubylib.join(File::PATH_SEPARATOR)
    env
  end

  # True when this Ruby build cannot even load rubygems without its stdlib
  # dirs on RUBYLIB. Stock builds resolve stdlib on their own; relocated
  # builds (non-default prefix) do not. Probed once per runner.
  def ruby_needs_stdlib_dirs?
    return @ruby_needs_stdlib_dirs unless @ruby_needs_stdlib_dirs.nil?

    @ruby_needs_stdlib_dirs = !system({ "RUBYLIB" => nil, "RUBYOPT" => nil },
                                      RbConfig.ruby, "-e", "require 'rubygems'",
                                      out: File::NULL, err: File::NULL)
  end

  def check_expectations(expect, results, dir)
    last = results.last
    problems = []
    problems << "exit #{last.status}, expected #{expect['exit']}" if expect["exit"] && last.status != expect["exit"]
    problems.concat(check_text(expect, last.text))
    problems.concat(check_json(expect, last)) if last.json
    problems << "no report.json written, so JSON expectations were not checked" if needs_json?(expect) && !last.json
    problems.concat(check_file_written(expect, dir))
    problems.concat(check_ranking(expect, last)) if expect["ranked_first"] || expect["ranked_top3"]
    problems.concat(check_deterministic(expect["deterministic"], results)) if expect["deterministic"]
    problems
  end

  def check_text(expect, text)
    problems = []
    Array(expect["stdout_includes"]).each do |needle|
      problems << "output does not include #{needle.inspect}" unless text.include?(needle)
    end
    Array(expect["stdout_excludes"]).each do |needle|
      problems << "output unexpectedly includes #{needle.inspect}" if text.include?(needle)
    end
    Array(expect["stdout_matches"]).each do |pattern|
      problems << "output does not match /#{pattern}/" unless text.match?(Regexp.new(pattern))
    end
    Array(expect["stdout_not_matches"]).each do |pattern|
      problems << "output unexpectedly matches /#{pattern}/" if text.match?(Regexp.new(pattern))
    end
    problems
  end

  def check_file_written(expect, dir)
    return [] unless expect["file_written"]

    File.file?(File.join(dir, expect["file_written"])) ? [] : ["proposal not written: #{expect['file_written']}"]
  end

  def needs_json?(expect)
    expect["survivors"] || expect["killed_credited_to"] || expect["mutants"]
  end

  def mutants(json)
    json.fetch("files").values.flat_map { |file| file.fetch("mutants") }
  end

  def check_json(expect, run)
    problems = []
    problems.concat(check_survivor_count(expect, run))
    problems.concat(check_score(expect, run))
    problems.concat(check_credit(expect, run))
    Array(expect["mutants"]).each { |want| problems.concat(check_mutant(want, run)) }
    problems
  end

  def check_survivor_count(expect, run)
    return [] unless (count = expect["survivors"])

    actual = mutants(run.json).count { |m| m["status"] == "Survived" }
    actual == count ? [] : ["#{actual} survivors, expected #{count}"]
  end

  def check_score(expect, run)
    return [] unless (score = expect["score"])

    actual = run.text[/Score: ([\d.]+%)/, 1]
    actual == score ? [] : ["score #{actual.inspect}, expected #{score.inspect}"]
  end

  def check_credit(expect, run)
    return [] unless (credit = expect["killed_credited_to"])

    names = test_names(run.json)
    killed = mutants(run.json).select { |m| m["status"] == "Killed" }
    credited = killed.count do |m|
      Array(m["killedBy"]).any? { |id| names.fetch(id, "").sub(%r{\A\./}, "").sub(/\[.*\z/, "") == credit["file"] }
    end
    return [] if credited == credit["count"]

    ["#{credited} kills credited to #{credit['file']}, expected #{credit['count']}"]
  end

  def check_mutant(want, run)
    candidates = mutants(run.json).select { |m| m["replacement"] == want.fetch("match").fetch("replacement") }
    return ["no mutant with replacement #{want['match']['replacement'].inspect}"] if candidates.empty?

    fields = %w[status gapKind classification valueDiffered].select { |field| want.key?(field) }
    return [] if candidates.any? { |m| fields.all? { |field| m[field] == want[field] } }

    lines = candidates.map { |m| candidate_misses(m, fields, want) }
    ["mutant #{want['match']['replacement'].inspect}: no single mutant matches every field - #{lines.join(' | ')}"]
  end

  def candidate_misses(mutant, fields, want)
    misses = fields.reject { |field| mutant[field] == want[field] }
                   .map { |field| "#{field} is #{mutant[field].inspect}, expected #{want[field].inspect}" }
    "#{mutant['id'] || 'candidate'}: #{misses.join('; ')}"
  end

  def test_names(json)
    json.fetch("testFiles").values.flat_map { |file| file.fetch("tests") }.to_h { |t| [t["id"], t["name"]] }
  end

  def check_ranking(expect, run)
    ranked = parse_ranked(run.text)
    return ["could not parse the ranked survivors list"] if ranked.empty?

    check_ranked_first(expect, ranked) + check_ranked_top3(expect, ranked)
  end

  def parse_ranked(text)
    text.scan(RANK_LINE).map do |rank, path, line, label|
      { rank: rank.to_i, path:, line: line.to_i, label: }
    end
  end

  def check_ranked_first(expect, ranked)
    return [] unless (first = expect["ranked_first"])

    top = ranked.first
    return [] if top[:path].end_with?(first["file_suffix"]) && top[:line] == first["line"]

    ["rank #1 is #{top[:path]}:#{top[:line]}, expected #{first['file_suffix']}:#{first['line']}"]
  end

  def check_ranked_top3(expect, ranked)
    top3 = ranked.select { |entry| entry[:rank] <= 3 }
    Array(expect["ranked_top3"]).filter_map do |want|
      labels = Array(want["label"])
      next if top3.any? { |entry| entry[:line] == want["line"] && labels.include?(entry[:label]) }

      actual = top3.map { |entry| "#{entry[:path]}:#{entry[:line]} #{entry[:label]}" }.join("; ")
      "no top-3 entry at line #{want['line']} labelled #{labels.join(' or ')} (top 3: #{actual})"
    end
  end

  def check_deterministic(fields, results)
    fingerprints = results.map do |run|
      return ["no report.json written on a repeated run"] unless run.json

      mutants(run.json).map { |m| fields.map { |f| m[f] } }.sort
    end
    fingerprints.uniq.size == 1 ? [] : ["reports differ across #{results.size} runs on #{fields.join(', ')}"]
  end

  def git(dir, *args)
    out, status = Open3.capture2e("git", "-C", dir, *args)
    raise "git #{args.first} failed in #{dir}:\n#{out}" unless status.success?
  end

  def print_summary
    @out.puts "\n== acceptance summary"
    if @failures.zero?
      @out.puts "   #{@cases} case(s), all passed"
    else
      @out.puts "   #{@cases} case(s), #{@failures} FAILED - compare with the maintainer's expectations above"
    end
  end
end

exit AcceptanceRunner.new.run if __FILE__ == $PROGRAM_NAME
