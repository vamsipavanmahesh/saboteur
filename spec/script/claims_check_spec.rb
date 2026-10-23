# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "fileutils"
require "tmpdir"

load File.expand_path("../../script/claims-check", __dir__)

# Drives ClaimsCheck against throwaway README/CHANGELOG trees, so a checker
# regression (a missed claim, a dead ref accepted) fails here, not in a
# release.
RSpec.describe "script/claims-check" do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = dir
      example.run
    end
  end

  def write(relative, content)
    path = File.join(@root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def spec_file(name = "spec/e2e/proof_spec.rb")
    write(name, "RSpec.describe 'x' do\n  it 'works' do\n    expect(1).to eq(1)\n  end\nend\n")
  end

  before do
    write("CHANGELOG.md", "# Changelog\n")
    write("README.md", "# x\n")
  end

  it "passes when every claim carries a live ref" do
    spec_file
    write("README.md", "## Highlights\n\n- Fast. (e2e: spec/e2e/proof_spec.rb)\n")
    expect(ClaimsCheck.run(@root)).to eq([])
  end

  it "fails when a Highlights bullet has no ref" do
    write("README.md", "## Highlights\n\n- Fast.\n")
    failures = ClaimsCheck.run(@root)
    expect(failures.size).to eq(1)
    expect(failures.first).to include("claim lacks an (e2e:")
  end

  it "folds a wrapped bullet's continuation lines into its ref scan" do
    spec_file
    write("README.md", "## Highlights\n\n- Fast when you\n  scope it. (e2e: spec/e2e/proof_spec.rb)\n")
    expect(ClaimsCheck.run(@root)).to eq([])
  end

  it "fails when the referenced spec does not exist" do
    write("README.md", "## Highlights\n\n- Fast. (e2e: spec/e2e/nope_spec.rb)\n")
    expect(ClaimsCheck.run(@root).first).to include("referenced spec does not exist")
  end

  it "fails when the referenced spec has no example" do
    write("spec/e2e/empty_spec.rb", "# nothing here\n")
    write("README.md", "## Highlights\n\n- Fast. (e2e: spec/e2e/empty_spec.rb)\n")
    expect(ClaimsCheck.run(@root).first).to include("referenced spec has no example")
  end

  it "checks Know the limits bullets but not other sections" do
    write("README.md", "## Know the limits\n\n- RSpec only.\n\n## Other\n\n- Free text.\n")
    failures = ClaimsCheck.run(@root)
    expect(failures.size).to eq(1)
    expect(failures.first).to include("RSpec only")
  end

  it "checks the Unreleased CHANGELOG section" do
    write("CHANGELOG.md", "## [Unreleased]\n\n- New thing.\n")
    failures = ClaimsCheck.run(@root)
    expect(failures.size).to eq(1)
    expect(failures.first).to include("CHANGELOG.md")
  end

  it "exempts a CHANGELOG section with a matching git tag" do
    spec_file
    write("CHANGELOG.md", "## [1.2.3]\n\n- Old thing.\n")
    Dir.chdir(@root) do
      system("git init -q && git add -A && git -c user.email=a@a -c user.name=a commit -qm x && git tag v1.2.3",
             out: File::NULL, err: File::NULL) or raise "git setup failed"
    end
    expect(ClaimsCheck.run(@root)).to eq([])
  end

  it "fails a versioned CHANGELOG section with no matching tag" do
    write("CHANGELOG.md", "## [9.9.9]\n\n- Future thing.\n")
    failures = ClaimsCheck.run(@root)
    expect(failures.size).to eq(1)
    expect(failures.first).to include("CHANGELOG.md")
  end
end
