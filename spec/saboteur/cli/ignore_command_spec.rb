# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "stringio"
require "tmpdir"

# saboteur ignore --check (plan-PR 15 slice b): the ignore ratchet. Stale
# entries are decided only from a full, complete .saboteur/report.json; a
# partial report leaves every entry unknown. --prune lands in slice c; the
# brief's golden block gains its prune hint line there.
RSpec.describe Saboteur::CLI, "ignore ratchet (plan-PR 15)" do
  # The golden block carries a UTF-8 arrow; pin the locale so a C-locale CI
  # leg does not downgrade it to the ASCII fallback.
  around do |example|
    saved = ENV.to_h.slice("LC_ALL", "LC_CTYPE", "LANG")
    ENV["LC_ALL"] = "C.UTF-8"
    example.run
  ensure
    keys = %w[LC_ALL LC_CTYPE LANG]
    keys.each { |key| saved.key?(key) ? ENV[key] = saved[key] : ENV.delete(key) }
  end

  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  let(:gone_digest) { "aaaa1111bbbb2222" }
  let(:won_digest) { "cccc3333dddd4444" }
  let(:live_digest) { "eeee5555ffff6666" }
  let(:ignore_text) do
    <<~RUBY
      # SPDX-License-Identifier: MIT
      # frozen_string_literal: true

      Saboteur.ignore do |i|
        # money stays integers here
        i.mutation "#{gone_digest}",
                   subject: "Billing::Invoice#total",
                   reason: "equivalent: money is integers here"
        i.mutation "#{won_digest}", subject: "Cart#total", reason: "won't fix: display only", state: "wont_fix"
        i.mutation "#{live_digest}", subject: "Cart#count", reason: "todo: cover next sprint", state: "todo"
      end
    RUBY
  end

  def mutant(id, status)
    { "id" => id, "mutatorName" => "sum_to_map_sum", "replacement" => "items.map(&:price).sum",
      "location" => { "start" => { "line" => 3, "column" => 3 }, "end" => { "line" => 3, "column" => 24 } },
      "status" => status }
  end

  def report(scope: "full", complete: true)
    { "schemaVersion" => "2", "thresholds" => { "high" => 80, "low" => 60 },
      "projectRoot" => Dir.pwd,
      "files" => { "lib/cart.rb" => { "language" => "ruby", "source" => "class Cart\nend\n",
                                      "mutants" => [mutant(won_digest, "Killed"), mutant(live_digest, "Survived")] } },
      "testFiles" => {},
      "saboteur" => { "scope" => scope, "complete" => complete } }
  end

  def in_project(with_report: true, report_value: report)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      FileUtils.mkdir_p(File.join(dir, ".saboteur"))
      File.write(File.join(dir, "config/saboteur_ignore.rb"), ignore_text)
      File.write(File.join(dir, ".saboteur/report.json"), JSON.generate(report_value)) if with_report
      Dir.chdir(dir) { yield dir }
    end
  end

  def cli(*argv)
    described_class.new(argv, out:, err:).call
  ensure
    ENV.delete("FORCE_COLOR")
  end

  it "prints the pinned block with both staleness kinds and exits 1 (monochrome and colour)" do
    in_project do
      expect(cli("ignore", "--check")).to eq(1)
      expect(out.string).to eq(<<~OUT)
        ignore ratchet: 2 stale entries in config/saboteur_ignore.rb
          aaaa11... Billing::Invoice#total - mutant no longer generated (code changed)
          cccc33... Cart#total - killed on the last full run (delete to lock the win)
        exit 1 - 2 stale ignore entries
      OUT
      out.truncate(0) && out.rewind
      ENV["FORCE_COLOR"] = "1"
      expect(cli("ignore", "--check")).to eq(1)
      expect(out.string).to include("\e[1mignore ratchet:\e[0m", "\e[33maaaa11...\e[0m",
                                    "\e[31;1mexit 1 - 2 stale ignore entries\e[0m")
    end
  end

  it "exits 0 when every entry is live" do
    live = report
    live["files"]["lib/cart.rb"]["mutants"] = [mutant(gone_digest, "Survived"), mutant(won_digest, "Survived"),
                                               mutant(live_digest, "Survived")]
    in_project(report_value: live) do
      expect(cli("ignore", "--check")).to eq(0)
      expect(out.string).to eq("ignore ratchet: config/saboteur_ignore.rb is clean (3 entries checked)\n")
    end
  end

  it "reports every entry as unknown when the report is a partial run" do
    in_project(report_value: report(scope: "diff")) do
      expect(cli("ignore", "--check")).to eq(0)
      note = "aaaa11... Billing::Invoice#total - unknown - the last report is not a full run; not pruned"
      expect(out.string).to include(note)
    end
  end

  it "exits 2 with a help line when no report exists" do
    in_project(with_report: false) do
      expect(cli("ignore", "--check")).to eq(2)
      expect(err.string).to include("run a full saboteur run first")
    end
  end
end
