# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require_relative "support"

RSpec.describe "script/preflight", :fixture do
  let(:entrypoint) { File.expand_path("../../../script/preflight", __dir__) }

  def invoke(*arguments)
    Open3.capture3(RbConfig.ruby, entrypoint, *arguments, chdir: @fixture.directory)
  end

  it "exits 2 on an unknown option" do
    _out, err, status = invoke("--allow-protected", "yes")
    expect([status.exitstatus, err]).to match([2, /unknown option/])
  end

  it "exits 2 on an abbreviated SHA" do
    _out, _err, status = invoke("--base", "abc", "--head", "def", "--base-ref", "main", "--mode", "fast")
    expect(status.exitstatus).to eq(2)
  end

  it "exits 2 when HEAD is not the requested head" do
    head = @fixture.head
    _out, err, status = invoke("--base", head, "--head", "f" * 40, "--base-ref", "main", "--mode", "fast")
    expect([status.exitstatus, err]).to match([2, /preflight:/])
  end

  it "exits 1 and names the failing check when a protected file changed" do
    @fixture.write(".github/workflows/evil.yml", "x\n")
    @fixture.commit("workflow")
    out, err, status = invoke("--base", @base, "--head", @fixture.head, "--base-ref", "main", "--mode", "fast")
    expect([status.exitstatus, out, err]).to match([1, /protected_paths \| failed/, ""])
  end

  def run_fast
    invoke("--base", @base, "--head", @fixture.head, "--base-ref", "main", "--mode", "fast")
  end

  it "does not traceback on a duplicate-key policy; it reports a failed or incomplete verdict" do
    @fixture.write("script/panel-gate/policy.json", '{"protectedFiles": [], "protectedFiles": []}')
    @fixture.commit("dup policy")
    base = @fixture.head
    @fixture.write("a.txt", "x\n")
    @fixture.commit("change")
    out, err, status = invoke("--base", base, "--head", @fixture.head, "--base-ref", "main", "--mode", "fast")
    expect([status.exitstatus, err, out]).to match([3, "", /protected_paths \| incomplete/])
  end

  it "does not traceback on an invalid policy document" do
    @fixture.write("script/panel-gate/policy.json", "not json")
    @fixture.commit("bad policy")
    base = @fixture.head
    @fixture.write("a.txt", "x\n")
    @fixture.commit("change")
    _out, err, status = invoke("--base", base, "--head", @fixture.head, "--base-ref", "main", "--mode", "fast")
    expect([status.exitstatus, err]).to eq([3, ""])
  end

  it "exits 3 with a clear message when the output directory cannot be created" do
    @fixture.write("a.txt", "x\n")
    @fixture.commit("change")
    File.write(File.join(@fixture.directory, "tmp"), "a file where the directory should be")
    @fixture.git("add", "-f", "tmp")
    @fixture.commit("block tmp")
    out, err, status = run_fast
    expect([status.exitstatus, err, out]).to match([3, /incomplete: .*tmp/, ""])
  end
end

RSpec.describe "preflight invocation form" do
  let(:root) { File.expand_path("../../..", __dir__) }

  it "documents and reports only the `ruby script/preflight` form, never direct execution" do
    %w[README.md AGENTS.md docs/preflight.md].each do |file|
      text = File.read(File.join(root, file))
      direct = text.lines.grep(%r{(?<!ruby )(?<![\w/.])script/preflight --})
      expect(direct).to eq([]), "#{file} runs script/preflight directly: #{direct.first}"
    end
  end

  it "gives contributors a command that works: AGENTS.md names --base, --head and --base-ref" do
    line = File.read(File.join(root, "AGENTS.md")).lines.find { |l| l.include?("ruby script/preflight") }
    expect(line).to include("--base <full main sha>", "--head <full head sha>", "--base-ref main")
  end

  it "has no shebang, because it is not executable and Lint/ScriptPermission would flag one" do
    expect(File.read(File.join(root, "script/preflight")).lines.first).not_to start_with("#!")
  end

  it "does not depend on the executable bit anywhere in the specs" do
    specs = Dir[File.join(root, "spec/script/preflight/*_spec.rb")]
    expect(specs.grep_v(/entrypoint_spec/).select do |f|
      File.read(f).include?("File.executable?(entrypoint")
    end).to eq([])
    expect(File.read(File.join(root,
                               "spec/script/preflight/entrypoint_spec.rb"))).to include("RbConfig.ruby, entrypoint")
  end
end
