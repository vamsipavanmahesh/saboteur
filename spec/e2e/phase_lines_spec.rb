# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Glyphs are [✓v] and [·*]: the palette falls back to ASCII under LANG=C.
RSpec.describe "clean screen phase lines (end to end)", :e2e do
  let(:dir) do
    copy_fixture("people").tap do |path|
      FileUtils.mkdir_p(File.join(path, "lib"))
      File.write(File.join(path, "lib", "one.rb"), "module One\n  def self.one = 1\nend\n")
      File.write(File.join(path, "spec", "one_spec.rb"),
                 "require_relative \"../lib/one\"\nRSpec.describe(One) { it(\"is 1\") { expect(One.one).to eq(1) } }\n")
    end
  end

  it "prints the baseline, built coverage map and dots lines from the engine's own stats, then the cached form" do
    first = saboteur(dir, "lib/one.rb", "--test", "spec/one_spec.rb")
    expect(first.status).to eq(0), first.err + first.out
    reuse = "reused next run when the tree is unchanged"
    expect(first.out).to match(
      /^[✓v] baseline green \(\d+ passes?, [\d.]+s\)  [✓v] coverage map: built 1 test \([\d.]+s\) - #{reuse}$/
    )
    expect(first.out).to match(%r{^\.+  \(\d+/\d+ [·*] [\d.]+s\)$})

    second = saboteur(dir, "lib/one.rb", "--test", "spec/one_spec.rb")
    expect(second.out).to match(/^[✓v] baseline green \(\d+ passes?, [\d.]+s\)  [✓v] coverage map: 1 test \(cached\)$/)
  end

  it "names the real scope under --since and the HTML report that was written" do
    system("git", "init", "-q", chdir: dir)
    system("git", "-c", "user.name=t", "-c", "user.email=t@t", "add", "-A", chdir: dir)
    system("git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base", chdir: dir)
    File.write(File.join(dir, "lib", "one.rb"), "module One\n  def self.one = 1\n  def self.two = 2\nend\n")
    spec = ["require_relative \"../lib/one\"", "RSpec.describe(One) do", "  it(\"is 1\") { expect(One.one).to eq(1) }",
            "  it(\"is 2\") { expect(One.two).to eq(2) }", "end", ""]
    File.write(File.join(dir, "spec", "one_spec.rb"), spec.join("\n"))
    run = saboteur(dir, "--since", "HEAD", "--test", "spec/one_spec.rb")
    expect(run.status).to eq(0), run.err + run.out
    expect(run.out).to match(/^saboteur \S+ [·*] --since HEAD [·*] seed \d+$/)
    expect(run.out).to include("  reports: .saboteur/report.html\n")
    expect(run.out).not_to include("next: saboteur run --since origin/main")
  end
end
