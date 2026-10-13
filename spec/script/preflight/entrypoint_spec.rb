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
    expect([status.exitstatus, err, out]).to match([3, /incomplete: output directory/, ""])
  end
end
