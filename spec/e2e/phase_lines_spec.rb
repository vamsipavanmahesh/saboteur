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
end
