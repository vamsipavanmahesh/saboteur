# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "inline suppression (end to end)", :e2e do
  it "audits suppressed candidates in terminal JSON and HTML" do
    dir = copy_fixture("inline")
    run = saboteur(dir)
    expect(run.status).to eq(0), run.err
    expect(mutants(run)).to be_empty
    entries = run.json.dig("saboteur", "inlineSuppressions")
    expect(entries.size).to be >= 4
    expect(entries.map { |entry| entry["reason"] }.uniq).to eq(["validated elsewhere"])
    expect(run.out).to include("Inline suppressions:", "validated elsewhere")
    html = File.read(File.join(dir, ".saboteur", "report.html"))
    expect(html).to include("Inline suppressions", "validated elsewhere")
  end

  [false, true].each do |subset|
    it "audits #{subset ? 'subset' : 'all'} suppressions in dry-run without output files" do
      dir = copy_fixture("inline")
      path = File.join(dir, "lib", "inline_math.rb")
      File.write(path, File.read(path).sub("disable-line reason", "disable-line arithmetic reason")) if subset
      before = Dir.glob("#{dir}/**/*", File::FNM_DOTMATCH).select { |file| File.file?(file) }
                  .to_h { |file| [file, File.binread(file)] }
      run = saboteur(dir, "--dry-run")
      expect(run.status).to eq(0), run.err
      expect(run.out).to include("Inline suppressions:", "before diff restriction and per-method cap",
                                 "InlineMath#double arithmetic", "validated elsewhere")
      count = run.out[/Total: (\d+) mutants/, 1].to_i
      subset ? expect(count).to(be_positive) : expect(count).to(eq(0))
      after = Dir.glob("#{dir}/**/*", File::FNM_DOTMATCH).select { |file| File.file?(file) }
                 .to_h { |file| [file, File.binread(file)] }
      expect(after).to eq(before)
    end
  end

  it "rejects a missing reason with exit 2 naming the directive line" do
    dir = copy_fixture("inline")
    path = File.join(dir, "lib", "inline_math.rb")
    File.write(path, File.read(path).sub('reason="validated elsewhere"', ""))
    run = saboteur(dir)
    expect(run.status).to eq(2)
    expect(run.err).to include("inline_math.rb:3:", "reason")
  end
  it "keeps classic score behavior but reports partial agent evidence for subset suppression" do
    dir = copy_fixture("inline")
    path = File.join(dir, "lib", "inline_math.rb")
    File.write(path, File.read(path).sub("disable-line reason", "disable-line arithmetic reason"))
    run = saboteur(dir, "--agent")
    expect(run.status).to eq(3), run.err
    payload = JSON.parse(run.out)
    expect(payload).to include("status" => "partial", "verdict" => "incomplete")
    expect(payload.fetch("incomplete")).to include(a_hash_including("reason" => "inline_suppressed", "count" => 1))
    expect(mutants(run)).not_to be_empty
  end

  it "blocks baseline completeness for a real subset-suppressed run" do
    dir = copy_fixture("inline")
    path = File.join(dir, "lib", "inline_math.rb")
    File.write(path, File.read(path).sub("disable-line reason", "disable-line arithmetic reason"))
    script = <<~RUBY
      require "coverage"
      Coverage.setup(lines: true, methods: true)
      require "saboteur"
      require "json"
      report = Saboteur::Engine.new(Saboteur::Config.load, capture_evidence: true).call
      File.write("evidence.json", JSON.generate(report.run_evidence))
    RUBY
    out, err, status = Open3.capture3({ "BUNDLE_GEMFILE" => File.join(E2EHelpers::ROOT, "Gemfile") },
                                      RbConfig.ruby, "-I", File.join(E2EHelpers::ROOT, "lib"), "-e", script, chdir: dir)
    expect(status.exitstatus).to eq(0), out + err
    evidence = JSON.parse(File.read(File.join(dir, "evidence.json")))
    expect(evidence.fetch("complete")).to be(false)
    expect(evidence.fetch("issues").grep(/inline_suppressed/).size).to eq(1)
    expect(evidence.fetch("inline_suppressions").first).to include("file" => "lib/inline_math.rb",
                                                                   "reason" => "validated elsewhere",
                                                                   "operator" => "arithmetic")
    expect(evidence.fetch("planned")).not_to be_empty
    expect(evidence.fetch("planned").map { |entry| entry.fetch("id") }.sort)
      .to eq(evidence.fetch("candidates").map { |entry| entry.fetch("id") }.sort)
  end
end
