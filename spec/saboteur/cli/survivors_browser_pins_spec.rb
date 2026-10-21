# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "json"
require "stringio"
require "tmpdir"

# Exact-output pins for the survivors browser layer (#520): list header,
# filters note, truncated-findings suffix and its limit fallback, row
# format, default and ranked order with every sort key element made
# decisive, the show view (diff, replay command, ignore-entry template,
# findings/accepted/source-line fallbacks, short digest prefixes) and
# both load_survivor_report refusal messages.
RSpec.describe Saboteur::CLI::SurvivorsBrowser, "output pins (#520)" do
  def mut(digest, operator, line, covered, classification = nil, status: "Survived")
    m = { "id" => digest, "mutatorName" => operator, "replacement" => "REPL_#{operator}",
          "location" => { "start" => { "line" => line, "column" => 3 },
                          "end" => { "line" => line, "column" => 9 } },
          "status" => status, "coveredBy" => covered }
    classification ? m.merge("classification" => classification) : m
  end

  let(:report) do
    { "schemaVersion" => "2", "projectRoot" => "/tmp/x", "config" => { "seed" => 7 },
      "files" => {
        "lib/order.rb" => { "language" => "ruby",
                            "source" => "#{(1..8).map { |i| "line#{i}_of_order" }.join("\n")}\n",
                            "mutants" => [mut("h" * 16, "literal_number", 7, []),
                                          mut("0" * 16, "comparison", 7, []),
                                          mut("e" * 16, "condition_true", 4, %w[t1], "order_dependent"),
                                          mut("a" * 16, "sum_to_map_sum", 5, %w[t1 t2 t3 t4], "missing_test"),
                                          mut("b" * 16, "and_to_or", 3, []),
                                          mut("c" * 16, "negation_removal", 6, %w[t1], status: "Killed")] },
        "lib/alpha.rb" => { "language" => "ruby",
                            "source" => "#{(1..9).map { |i| "alpha#{i}" }.join("\n")}\n",
                            "mutants" => [mut("f" * 16, "body_nil", 9, [])] },
        "lib/zeta.rb" => { "language" => "ruby", "source" => "zeta_one\nzeta_two\n",
                           "mutants" => [mut("d" * 16, "literal_string", 1, %w[t1 t2 t3 t4])] }
      },
      "saboteur" => { "findings" => { "version" => 1, "survivors" => [
        { "digest" => "e" * 16, "subject" => "Order#flag", "original" => "flag && x",
          "replacement" => "true" },
        { "digest" => "a" * 16, "subject" => "Order#total", "original" => "items.sum(&:price)",
          "replacement" => "items.map(&:price).sum" }
      ], "survivorsTruncated" => 2, "accepted" => [
        { "digest" => "d" * 16, "subject" => "Zeta#one", "original" => '"z"', "replacement" => '"Z"' }
      ] } } }
  end

  let(:browser) { described_class.new(report) }

  it "lists by path, line and digest - killed mutants excluded - with exact header and rows" do
    expect(browser.list).to eq(
      ["7 survivors (the report's ranked findings name only the first 10)",
       "  1. lib/alpha.rb:9  body_nil                     ffffffffffffffff  -",
       "  2. lib/order.rb:3  and_to_or                    bbbbbbbbbbbbbbbb  -",
       "  3. lib/order.rb:4  condition_true               eeeeeeeeeeeeeeee  order_dependent",
       "  4. lib/order.rb:5  sum_to_map_sum               aaaaaaaaaaaaaaaa  missing_test",
       "  5. lib/order.rb:7  comparison                   0000000000000000  -",
       "  6. lib/order.rb:7  literal_number               hhhhhhhhhhhhhhhh  -",
       "  7. lib/zeta.rb:1  literal_string               dddddddddddddddd  -"]
    )
  end

  it "ranks findings first, then unranked by coverage count, path, line and digest" do
    expect(browser.list(ranked: true)).to eq(
      ["7 survivors (the report's ranked findings name only the first 10)",
       "  1. lib/order.rb:4  condition_true               eeeeeeeeeeeeeeee  order_dependent",
       "  2. lib/order.rb:5  sum_to_map_sum               aaaaaaaaaaaaaaaa  missing_test",
       "  3. lib/zeta.rb:1  literal_string               dddddddddddddddd  -",
       "  4. lib/alpha.rb:9  body_nil                     ffffffffffffffff  -",
       "  5. lib/order.rb:3  and_to_or                    bbbbbbbbbbbbbbbb  -",
       "  6. lib/order.rb:7  comparison                   0000000000000000  -",
       "  7. lib/order.rb:7  literal_number               hhhhhhhhhhhhhhhh  -"]
    )
  end

  it "prints the singular header and triage note when a filter selects exactly one" do
    expect(browser.list(triage: "missing_test")).to eq(
      ["1 survivor (triage=missing_test) (the report's ranked findings name only the first 10)",
       "  1. lib/order.rb:5  sum_to_map_sum               aaaaaaaaaaaaaaaa  missing_test"]
    )
  end

  it "combines the file and operator notes verbatim" do
    expect(browser.list(file: "order", operator: "and_to_or")).to eq(
      ["1 survivor (file~order, operator=and_to_or) (the report's ranked findings name only the first 10)",
       "  1. lib/order.rb:3  and_to_or                    bbbbbbbbbbbbbbbb  -"]
    )
  end

  it "says no survivors with the filter note when nothing matches" do
    expect(browser.list(file: "zzz")).to eq("no survivors (file~zzz)")
  end

  it "names the findings limit when the report carries one" do
    limited = Marshal.load(Marshal.dump(report))
    limited["saboteur"]["findings"]["limit"] = 7
    expect(described_class.new(limited).list.first)
      .to eq("7 survivors (the report's ranked findings name only the first 7)")
  end

  it "omits the truncated suffix when no findings were truncated" do
    untruncated = Marshal.load(Marshal.dump(report))
    untruncated["saboteur"]["findings"].delete("survivorsTruncated")
    expect(described_class.new(untruncated).list.first).to eq("7 survivors")
  end

  it "works without a findings section at all, ranked included" do
    bare = described_class.new({ "files" => report["files"] })
    expect(bare.list.first).to eq("7 survivors")
    expect(bare.list(ranked: true).first).to eq("7 survivors")
    expect(bare.show("bbbb")).to include(
      "subject: \"Klass#meth\", reason: \"why it is equivalent\" " \
      "# TODO: capped findings omit this digest - fill in the subject"
    )
  end

  it "treats a survivor entry with a null coveredBy as zero coverage, ranked included" do
    # The Stryker writer emits null coveredBy for uncovered mutants.
    entry = { "id" => "9" * 16, "mutatorName" => "body_nil", "replacement" => "nil",
              "location" => { "start" => { "line" => 2, "column" => 3 },
                              "end" => { "line" => 2, "column" => 9 } },
              "status" => "Survived", "coveredBy" => nil }
    report = { "files" => { "lib/solo.rb" => { "language" => "ruby", "source" => "a\nb\nc\n",
                                               "mutants" => [entry] } } }
    expect(described_class.new(report).list(ranked: true)).to eq(
      ["1 survivor", "  1. lib/solo.rb:2  body_nil                     #{'9' * 16}  -"]
    )
  end

  it "treats a report without a files section as having no survivors" do
    expect(described_class.new({}).list).to eq("no survivors")
  end

  it "treats a file entry without a mutants list as having no survivors" do
    report = { "files" => { "lib/empty.rb" => { "language" => "ruby", "source" => "" } } }
    expect(described_class.new(report).list).to eq("no survivors")
  end

  it "shows one survivor from a short digest prefix: diff, replay and subject from findings" do
    expect(browser.show("aaaa")).to eq(
      "lib/order.rb:5  sum_to_map_sum  aaaaaaaaaaaaaaaa\n" \
      "\n" \
      "- items.sum(&:price)\n" \
      "+ items.map(&:price).sum\n" \
      "\n" \
      "replay one survivor: saboteur run --id aaaaaaaaaaaaaaaa --seed 7\n  " \
      "(add this run's own --config, --since, --subject, --test and source options)\n" \
      "\n" \
      "accept an equivalent one: add to your ignore file (c.ignore_file, default config/saboteur_ignore.rb):\n  " \
      "" \
      "i.mutation \"aaaaaaaaaaaaaaaa\", subject: \"Order#total\", reason: \"why it is equivalent\""
    )
  end

  it "falls back to the source line and the subject TODO for a digest the findings omit" do
    expect(browser.show("b" * 16)).to eq(
      "lib/order.rb:3  and_to_or  bbbbbbbbbbbbbbbb\n" \
      "\n" \
      "- line3_of_order\n" \
      "+ REPL_and_to_or\n" \
      "\n" \
      "replay one survivor: saboteur run --id bbbbbbbbbbbbbbbb --seed 7\n  " \
      "(add this run's own --config, --since, --subject, --test and source options)\n" \
      "\n" \
      "accept an equivalent one: add to your ignore file (c.ignore_file, default config/saboteur_ignore.rb):\n  " \
      "" \
      "i.mutation \"bbbbbbbbbbbbbbbb\", subject: \"Klass#meth\", reason: \"why it is equivalent\" " \
      "# TODO: capped findings omit this digest - fill in the subject"
    )
  end

  it "takes the subject and diff from an accepted finding" do
    expect(browser.show("dddd")).to eq(
      "lib/zeta.rb:1  literal_string  dddddddddddddddd\n" \
      "\n" \
      "- \"z\"\n" \
      "+ \"Z\"\n" \
      "\n" \
      "replay one survivor: saboteur run --id dddddddddddddddd --seed 7\n  " \
      "(add this run's own --config, --since, --subject, --test and source options)\n" \
      "\n" \
      "accept an equivalent one: add to your ignore file (c.ignore_file, default config/saboteur_ignore.rb):\n  " \
      "" \
      "i.mutation \"dddddddddddddddd\", subject: \"Zeta#one\", reason: \"why it is equivalent\""
    )
  end

  it "refuses an unknown digest prefix naming the digest" do
    expect { browser.show("0000 1") }
      .to raise_error(Saboteur::CLI::UsageError, "no survivor with digest 0000 1 in this report")
  end
end

RSpec.describe Saboteur::CLI, "survivors report loading (#520)" do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def cli(*argv)
    described_class.new(argv, out:, err:)
  end

  it "refuses a missing report with the verbatim message" do
    expect(cli("survivors", "no/such/report.json").call).to eq(2)
    expect(err.string).to eq("saboteur: report not found: no/such/report.json\n")
  end

  it "refuses a malformed report with the verbatim prefix and the parser detail" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bad.json")
      File.write(path, "{not json")
      expect(cli("survivors", path).call).to eq(2)
      prefix = "saboteur: #{path} is not a readable saboteur report: "
      expect(err.string).to start_with(prefix)
      expect(err.string.delete_prefix(prefix).strip).not_to be_empty
    end
  end
end
