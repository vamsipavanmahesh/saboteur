# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"
require "json"

# Score honesty: the score covers tested subjects only, and untested
# subjects are always named next to it. A file with nothing tested shows
# n/a, never a percentage; the closing lines say what the run found, how
# long it took, and why it exits the way it does.
RSpec.describe "score honesty" do
  # The goldens pin the UTF-8 glyphs; force a UTF-8 locale so a
  # C-locale CI leg does not downgrade them to their ASCII fallbacks.
  around do |example|
    saved = ENV.to_h.slice("LC_ALL", "LC_CTYPE", "LANG")
    ENV["LC_ALL"] = "C.UTF-8"
    example.run
  ensure
    keys = %w[LC_ALL LC_CTYPE LANG]
    keys.each { |key| saved.key?(key) ? ENV[key] = saved[key] : ENV.delete(key) }
  end
  after { FileUtils.rm_rf(dir) }

  let(:dir) { File.realpath(Dir.mktmpdir("saboteur-honesty-")) }
  let(:out) { StringIO.new }

  let(:cart_source) do
    <<~RUBY2
      class Cart
        def total
          @items.sum
        end

        def biggest
          @items.max
        end

        def discounted
          @count >= 1 ? total : 0
        end

        def smallest
          @count >= 2 ? @items.min : nil
        end
      end
    RUBY2
  end

  let(:calculator_source) do
    <<~RUBY2
      class Calculator
        def add
          @a >= 1 ? @a + @b : @b
        end

        def shipping_cost
          @weight * 2
        end
      end
    RUBY2
  end

  def subjects_for(name, source)
    path = File.join(dir, name)
    File.write(path, source)
    Saboteur::SubjectFinder.new.call(path).subjects
  end

  def result(subject, status, from: ">= 1", to: "> 1", coarse: false, **extra)
    at = subject.file_source.index(from)
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at, end_byte: at + from.length,
                                              replacement: to)
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id,
                                                      operator: coarse ? "body_nil" : "comparison",
                                                      edits: [edit], coarse:)
    Saboteur::MutantResult.new(subject:, mutation:, status:, mutated_source: subject.apply(mutation.edits), **extra)
  end

  # The brief's fixture: cart.rb has four subjects, two of them uncovered;
  # the old table said "100.0 %" for it and dropped the two silently.
  let(:cart) { subjects_for("cart.rb", cart_source).to_h { |subject| [subject.id, subject] } }
  let(:calculator) { subjects_for("calculator.rb", calculator_source).to_h { |subject| [subject.id, subject] } }
  let(:subjects) { cart.values + calculator.values }
  let(:results) do
    [result(cart.fetch("Cart#discounted"), :killed),
     result(cart.fetch("Cart#smallest"), :killed, from: ">= 2", to: "> 2"),
     result(calculator.fetch("Calculator#add"), :killed),
     result(calculator.fetch("Calculator#add"), :survived, to: "< 1"),
     result(calculator.fetch("Calculator#add"), :timeout, to: "== 1")]
  end
  let(:skipped) do
    { cart.fetch("Cart#total") => "no coverage", cart.fetch("Cart#biggest") => "no coverage",
      calculator.fetch("Calculator#shipping_cost") => "no coverage" }
  end
  let(:report) do
    Saboteur::Report.new(results:, subjects:, wall_time: 62.0, root: dir, seed: 7, skipped_subjects: skipped)
  end

  def render(report, **options)
    out.truncate(0)
    out.rewind
    Saboteur::Reporter::Terminal.new(out, **options).call(report)
    out.string
  end

  # The closing block, from the opener line to the verdict line.
  def closing(text)
    text[/^(\e\[2m)?saboteur #{Regexp.escape(Saboteur::VERSION)}:.*/m]
  end

  it "prints the honest golden, monochrome" do
    expected = <<~TEXT
      saboteur #{Saboteur::VERSION}: 6 subjects, 5 mutants, wall 62.00 s, seed 7 (repeat with --seed 7)
      Score: 80.0% (4/5 killed or timed out, tested subjects)  3 subjects not scored - no test executes them

      Score by file (worst first):
        calculator.rb   66.7% (2/3) · n/a - 1 subject - no test executes it: Calculator#shipping_cost
        cart.rb        100.0% (2/2) · n/a - 2 subjects - no test executes them: Cart#total, Cart#biggest

      Not scored - no test executes these (treat these as your biggest gaps):
        ! Calculator#shipping_cost (calculator.rb:6) · Cart#total (cart.rb:2) · Cart#biggest (cart.rb:6)
      saboteur: 3 killed, 1 survived, 1 timeout, 3 subjects untested in 1m02s - score 80.0%
      ✗ exit 1 - 1 survivor

      Next steps:
        replay one survivor: saboteur run --id #{digest} --seed 7
          (add this run's own --config, --since, --subject, --test and source options)
        accept an equivalent one: add to your ignore file (c.ignore_file, default config/saboteur_ignore.rb):
          Saboteur.ignore do |i|
            i.mutation "#{digest}", subject: "Calculator#add", reason: "why it is equivalent"
          end
        let an agent close the gaps: saboteur run --agent, with the same options
    TEXT
    text = render(report, color: :never, exit_code: 1)
    expect(closing(text)).to eq(expected)
    # The lie is gone: the old format and a bare 100.0 % for cart.rb.
    expect(text).not_to include("100.0 %", "survivors\n")
  end

  it "prints the honest golden with colour, one palette name per mock tag" do
    expected = <<~TEXT
      \e[2msaboteur #{Saboteur::VERSION}: 6 subjects, 5 mutants, wall 62.00 s, seed 7 (repeat with --seed 7)\e[0m
      Score: 80.0% (4/5 killed or timed out, tested subjects)  \e[33m3 subjects not scored - no test executes them\e[0m

      Score by file (worst first):
        calculator.rb   66.7% (2/3) · \e[33mn/a - 1 subject - no test executes it: Calculator#shipping_cost\e[0m
        cart.rb        100.0% (2/2) · \e[33mn/a - 2 subjects - no test executes them: Cart#total, Cart#biggest\e[0m

      \e[33mNot scored - no test executes these (treat these as your biggest gaps):\e[0m
        \e[33m!\e[0m Calculator#shipping_cost (calculator.rb:6) · Cart#total (cart.rb:2) · Cart#biggest (cart.rb:6)
      saboteur: \e[32m3 killed\e[0m, \e[31;1m1 survived\e[0m, \e[33m1 timeout\e[0m, 3 subjects untested in 1m02s - score 80.0%
      \e[31;1m✗ exit 1 - 1 survivor\e[0m

      \e[1mNext steps:\e[0m
        replay one survivor: \e[36msaboteur run --id #{digest} --seed 7\e[0m
          (add this run's own --config, --since, --subject, --test and source options)
        accept an equivalent one: add to your ignore file (c.ignore_file, default config/saboteur_ignore.rb):
          Saboteur.ignore do |i|
            i.mutation "#{digest}", subject: "Calculator#add", reason: "why it is equivalent"
          end
        let an agent close the gaps: saboteur run --agent, with the same options
    TEXT
    expect(closing(render(report, color: :always, exit_code: 1))).to eq(expected)
  end

  it "gives a file with nothing tested a pure n/a row, no percentage" do
    notes = subjects_for("notes.rb", "class Notes\n  def draft; 1; end\nend\n").first
    tested = calculator.fetch("Calculator#add")
    report = Saboteur::Report.new(results: [result(tested, :killed)], subjects: [tested, notes],
                                  wall_time: 1.0, root: dir, seed: 1,
                                  skipped_subjects: { notes => "no coverage" })
    table = Saboteur::Reporter::ScoreTable.new(out, Saboteur::Reporter::Palette.new(enabled: false))
    table.call(report)
    expect(out.string).to eq(
      "\nScore by file (worst first):\n  calculator.rb  100.0% (1/1)\n  " \
      "notes.rb       n/a - 1 subject - no test executes it: Notes#draft\n"
    )
    expect(out.string).not_to match(/notes\.rb.*%/)
  end

  def digest
    results.find(&:survived?).digest
  end

  describe "canonical summary line" do
    def line_for(results, wall: 1.25, skipped: {}, threshold: nil)
      report = Saboteur::Report.new(results:, subjects: [calculator.fetch("Calculator#add")], wall_time: wall,
                                    root: dir, seed: 1, skipped_subjects: skipped)
      render(report, color: :never, threshold: threshold).lines.find { |line| line.start_with?("saboteur: ") }
    end

    let(:add) { calculator.fetch("Calculator#add") }

    it "names survivors" do
      expect(line_for([result(add, :killed), result(add, :survived, to: "< 1"), result(add, :killed, to: "== 1"),
                       result(add, :killed, to: "<= 1")]))
        .to eq("saboteur: 3 killed, 1 survived in 1s - score 75.0%\n")
    end

    it "echoes the threshold when set" do
      line = line_for([result(add, :killed), result(add, :survived, to: "< 1"), result(add, :killed, to: "== 1"),
                       result(add, :killed, to: "<= 1")], threshold: 80)
      expect(line).to eq("saboteur: 3 killed, 1 survived in 1s - score 75.0% (threshold 80)\n")
    end

    it "names timeouts when there are some, counted as detected in the score" do
      line = line_for([result(add, :killed), result(add, :timeout, to: "< 1"), result(add, :timeout, to: "== 1")])
      expect(line).to eq("saboteur: 1 killed, 2 timeouts in 1s - score 100.0%\n")
    end

    it "names accepted survivors apart from live ones" do
      accepted = result(add, :survived, to: "< 1")
      accepted.ignored = "equivalent: ages are integers"
      expect(line_for([result(add, :killed), accepted])).to eq("saboteur: 1 killed, 1 accepted in 1s - score 50.0%\n")
    end

    it "always names untested subjects, and says score n/a when nothing was tested" do
      notes = subjects_for("notes.rb", "class Notes\n  def draft; 1; end\nend\n").first
      line = line_for([], wall: 0, skipped: { notes => "no coverage" })
      expect(line).to eq("saboteur: 1 subject untested in 0s - score n/a\n")
    end

    it "formats the duration as minutes and seconds" do
      expect(line_for([result(add, :killed)], wall: 62)).to include("in 1m02s -")
    end

    it "falls back to no mutants when there is nothing to count" do
      expect(line_for([], wall: 0)).to eq("saboteur: no mutants in 0s - score n/a\n")
    end
  end

  describe "verdict line" do
    def verdict_for(results, exit_code:, threshold: nil, review: false, skipped: {})
      report = Saboteur::Report.new(results:, subjects: [calculator.fetch("Calculator#add")], wall_time: 1.0,
                                    root: dir, seed: 1, review:, skipped_subjects: skipped)
      render(report, color: :never, exit_code:, threshold:).lines.find { |line| line.start_with?("\u2717") }
    end

    let(:add) { calculator.fetch("Calculator#add") }
    let(:surviving) { [result(add, :killed), result(add, :survived, to: "< 1")] }

    it "names survivors" do
      expect(verdict_for(surviving, exit_code: 1)).to eq("✗ exit 1 - 1 survivor\n")
      two = surviving + [result(add, :survived, to: "== 1")]
      expect(verdict_for(two, exit_code: 1)).to eq("✗ exit 1 - 2 survivors\n")
    end

    it "names a broken threshold with the score and the threshold" do
      accepted = result(add, :survived, to: "< 1")
      accepted.ignored = "equivalent: ages are integers"
      expect(verdict_for([result(add, :killed), accepted], exit_code: 1, threshold: 80))
        .to eq("✗ exit 1 - score 50.0% below threshold 80\n")
    end

    it "names both when the score is low and mutants survived" do
      expect(verdict_for(surviving, exit_code: 1, threshold: 60))
        .to eq("✗ exit 1 - score 50.0% below threshold 60, 1 survivor\n")
    end

    it "names an unverified change when every subject under review was skipped" do
      expect(verdict_for([], exit_code: 3, review: true, skipped: { add => "no coverage" }))
        .to eq("✗ exit 3 - 1 change could not be verified (no coverage)\n")
    end

    it "joins the skip reasons when several kept the change unverifiable" do
      shipping = calculator.fetch("Calculator#shipping_cost")
      report = Saboteur::Report.new(results: [], subjects: [add, shipping], wall_time: 1.0, root: dir, seed: 1,
                                    review: true, skipped_subjects: { add => "no coverage", shipping => "filtered" })
      expect(render(report, color: :never, exit_code: 3).lines.find { |line| line.start_with?("\u2717") })
        .to eq("\u2717 exit 3 - 2 changes could not be verified (no coverage, filtered)\n")
    end

    it "names a spent --max-duration budget on exit 4" do
      expect(verdict_for([result(add, :killed)], exit_code: 4))
        .to eq("\u2717 exit 4 - --max-duration budget spent; the score covers only completed work\n")
    end

    it "prints no verdict line on exit 0" do
      text = render(Saboteur::Report.new(results: [result(add, :killed)], subjects: [add], wall_time: 1.0,
                                         root: dir, seed: 1), color: :never, exit_code: 0)
      expect(text).not_to include("✗")
      expect(text.lines.last).to eq("  next: saboteur run --since origin/main\n")
    end
  end

  describe "score band colours" do
    let(:add) { calculator.fetch("Calculator#add") }
    let(:band_report) do
      Saboteur::Report.new(results: [result(add, :killed), result(add, :survived, to: "< 1")], subjects: [add],
                           wall_time: 1.0, root: dir, seed: 1)
    end

    it "paints the score red below the threshold, green at or above it, plain without one" do
      expect(render(band_report, color: :always, threshold: 80)).to include("\e[31;1m50.0%\e[0m")
      clean = Saboteur::Report.new(results: [result(add, :killed)], subjects: [add], wall_time: 1.0, root: dir,
                                   seed: 1)
      expect(render(clean, color: :always, threshold: 80)).to include("\e[32m100.0%\e[0m")
      expect(render(band_report, color: :always, threshold: 50)).to include("\e[32m50.0%\e[0m")
      text = render(band_report, color: :always)
      expect(text).to include("Score: 50.0% (1/2 killed, tested subjects)")
    end

    it "has a yellow state only inside a wider (low, high) band" do
      terminal = Saboteur::Reporter::Terminal.new(out)
      expect(terminal.send(:band_color, 70, 60, 80)).to eq(:warn)
      expect(terminal.send(:band_color, 50, 60, 80)).to eq(:fail)
      expect(terminal.send(:band_color, 80, 60, 80)).to eq(:pass)
      expect(terminal.send(:band_color, 75, 80, 80)).to eq(:fail)
    end
  end

  describe "score headline" do
    let(:add) { calculator.fetch("Calculator#add") }
    let(:headline_report) do
      Saboteur::Report.new(results: [result(add, :killed), result(add, :survived, to: "< 1")], subjects: [add],
                           wall_time: 1.0, root: dir, seed: 1)
    end

    def headline_for(report, **options)
      render(report, **options).lines.find { |line| line.start_with?("Score:") }
    end

    it "echoes the threshold and marks a break, dim when met" do
      expect(headline_for(headline_report, color: :never, threshold: 80))
        .to include("Score: 50.0% · threshold 80 (break)")
      expect(headline_for(headline_report, color: :never, threshold: 50))
        .to include("Score: 50.0% · threshold 50")
      expect(headline_for(headline_report, color: :never, threshold: 50)).not_to include("(break)")
      expect(headline_for(headline_report, color: :never)).not_to include("threshold")
    end

    it "paints the echo red on a break and dim when met" do
      expect(headline_for(headline_report, color: :always, threshold: 80))
        .to include("\e[31;1m · threshold 80 (break)\e[0m")
      expect(headline_for(headline_report, color: :always, threshold: 50))
        .to include("\e[2m · threshold 50\e[0m")
    end

    it "names the previous score from the history, dim" do
      expect(headline_for(headline_report, color: :never, previous_score: 0.732)).to include("· prev 73.2%")
      expect(headline_for(headline_report, color: :always, previous_score: 0.732))
        .to include("\e[2m · prev 73.2%\e[0m")
      expect(headline_for(headline_report, color: :never)).not_to include("prev")
    end
  end

  describe "verbose score split" do
    let(:add) { calculator.fetch("Calculator#add") }
    let(:split_report) do
      Saboteur::Report.new(results: [result(add, :killed, kill_cause: "assertion"),
                                     result(add, :killed, to: "< 1", kill_cause: "NoMethodError")],
                           subjects: [add], wall_time: 1.0, root: dir, seed: 1)
    end

    it "prints the split under --verbose only" do
      expect(render(split_report, color: :never, verbose: true)).to include("(assertion 50.0 %, crash 50.0 %)")
      expect(render(split_report, color: :never)).not_to include("(assertion")
    end

    it "prints the whole-body split under --verbose only" do
      report = Saboteur::Report.new(results: [result(add, :killed, kill_cause: "assertion"),
                                              result(add, :killed, to: "< 1", coarse: true)],
                                    subjects: [add], wall_time: 1.0, root: dir, seed: 1)
      expect(render(report, color: :never, verbose: true)).to include("score without whole-body mutants")
      expect(render(report, color: :never)).not_to include("without whole-body mutants")
    end
  end

  it "keeps the terminal's honesty wording out of the machine reports" do
    json = JSON.generate(Saboteur::Reporter::Stryker.build(report))
    expect(json).not_to include("Not scored", "no test executes", "✗", "✓")
    expect(JSON.parse(json)["skippedSubjects"].map { |entry| entry["subject"] })
      .to contain_exactly("Cart#total", "Cart#biggest", "Calculator#shipping_cost")
  end
  # Each example feeds its check the input that exposes a dogfood survivor
  # mutant on this branch: counts of two for the plurals, out-of-order
  # insertion for the sort, mixed skip reasons for the filter, more items
  # than the cap for the cap.
  describe "dogfood survivor kills" do
    let(:add) { calculator.fetch("Calculator#add") }
    let(:shipping) { calculator.fetch("Calculator#shipping_cost") }

    def honest_report(results, skipped: {}, subjects: [calculator.fetch("Calculator#add")], wall: 1.0, **extra)
      Saboteur::Report.new(results:, subjects:, wall_time: wall, root: dir, seed: 1,
                           skipped_subjects: skipped, **extra)
    end

    def canonical(results, **report_options)
      render(honest_report(results, **report_options), color: :never)
        .lines.find { |line| line.start_with?("saboteur: ") }
    end

    def verdict_line_for(report, exit_code, threshold: nil)
      render(report, color: :never, exit_code:, threshold:).lines.find { |line| line.start_with?("\u2717") }
    end

    it "never adds an s to survived, accepted or unverified, whatever the count" do
      two = [result(add, :survived, to: "< 1"), result(add, :survived, to: "== 1")]
      expect(canonical(two)).to eq("saboteur: 2 survived in 1s - score 0.0%\n")
      accepted = [result(add, :survived, to: "< 1"), result(add, :survived, to: "== 1")]
      accepted.each { |entry| entry.ignored = "equivalent: boundary" }
      expect(canonical([result(add, :killed)] + accepted)).to eq("saboteur: 1 killed, 2 accepted in 1s - score 33.3%\n")
      unverified = [result(add, :unverified, to: "< 1"), result(add, :unverified, to: "== 1")]
      expect(canonical(unverified)).to eq("saboteur: 2 unverified in 1s - score n/a\n")
    end

    it "keeps the accepted count unpainted when colour is on" do
      accepted = result(add, :survived, to: "< 1")
      accepted.ignored = "equivalent: boundary"
      line = render(honest_report([result(add, :killed), accepted]), color: :always)
             .lines.find { |entry| entry.start_with?("saboteur: ") }
      expect(line).to include("\e[32m1 killed\e[0m")
      expect(line).to include("1 accepted")
    end

    it "lists only no-coverage subjects as untested, in file and line order" do
      skipped = { cart.fetch("Cart#biggest") => "no coverage", cart.fetch("Cart#total") => "no coverage",
                  add => "filtered" }
      text = render(honest_report([result(add, :killed)], skipped:, subjects:), color: :never)
      expect(text).to include("n/a - 2 subjects - no test executes them: Cart#total, Cart#biggest")
      expect(text).to include("! Cart#total (cart.rb:2) · Cart#biggest (cart.rb:6)")
      expect(text).to include("2 subjects not scored - no test executes them")
      expect(text).not_to include("3 subjects")
      calc_row = text.lines.find { |line| line.start_with?("  calculator.rb") }
      expect(calc_row.strip).to eq("calculator.rb  100.0% (1/1)")
    end

    it "caps the untested names on a file row and counts the rest" do
      skipped = cart.values.to_h { |subject| [subject, "no coverage"] }
      text = render(honest_report([result(add, :killed)], skipped:, subjects:), color: :never)
      row = text.lines.find { |line| line.start_with?("  cart.rb") }
      expect(row).to include("4 subjects - no test executes them: Cart#total, Cart#biggest, Cart#discounted, +1 more")
      expect(row).not_to include("Cart#smallest")
    end

    it "names up to three untested subjects without a count-off tail" do
      skipped = cart.values.first(3).to_h { |subject| [subject, "no coverage"] }
      text = render(honest_report([result(add, :killed)], skipped:, subjects:), color: :never)
      row = text.lines.find { |line| line.start_with?("  cart.rb") }
      expect(row).to include("3 subjects - no test executes them: Cart#total, Cart#biggest, Cart#discounted")
      expect(row).not_to include("more")
    end

    it "caps the Not scored block at ten entries and counts the rest" do
      methods = (1..11).map { |i| "  def m#{i}\n    #{i}\n  end\n" }.join
      source = "class Many\n#{methods}end\n"
      many = subjects_for("many.rb", source)
      skipped = many.to_h { |subject| [subject, "no coverage"] }
      text = render(honest_report([result(add, :killed)], skipped:, subjects: [add] + many), color: :never)
      block = text.lines.find { |line| line.start_with?("  !") }
      expect(block.scan("Many#m").size).to eq(10)
      expect(block).to include("· ... 1 more")
      expect(block).not_to include("Many#m11")
    end

    it "counts the exact overflow past ten not-scored entries" do
      methods = (1..23).map { |i| "  def m#{i}\n    #{i}\n  end\n" }.join
      source = "class Many\n#{methods}end\n"
      many = subjects_for("many.rb", source)
      skipped = many.to_h { |subject| [subject, "no coverage"] }
      text = render(honest_report([result(add, :killed)], skipped:, subjects: [add] + many), color: :never)
      block = text.lines.find { |line| line.start_with?("  !") }
      expect(block).to include(" · ... 13 more")
    end

    it "prints no count-off tail when the Not scored block exactly fills" do
      methods = (1..10).map { |i| "  def t#{i}\n    #{i}\n  end\n" }.join
      source = "class Ten\n#{methods}end\n"
      ten = subjects_for("ten.rb", source)
      skipped = ten.to_h { |subject| [subject, "no coverage"] }
      text = render(honest_report([result(add, :killed)], skipped:, subjects: [add] + ten), color: :never)
      block = text.lines.find { |line| line.start_with?("  !") }
      expect(block.scan("Ten#t").size).to eq(10)
      expect(block).not_to include("more")
    end

    it "prints no Not scored block and no untested note on a fully tested run" do
      text = render(honest_report([result(add, :killed)]), color: :never)
      expect(text).not_to include("Not scored")
      expect(text).not_to include("not scored")
    end

    it "keeps the skipped-subjects lines under --verbose only" do
      expect(render(report, color: :never)).not_to include("methods never run by tests")
      expect(render(report, color: :never, verbose: true)).to include("methods never run by tests: 3")
    end

    it "keeps mutant skip reasons under --verbose only" do
      filtered = result(add, :skipped, to: "< 1", reason: "filtered")
      results = [result(add, :killed), filtered]
      expect(render(honest_report(results), color: :never)).not_to include("skipped: filtered")
      expect(render(honest_report(results), color: :never, verbose: true)).to include("skipped: filtered: 1")
    end

    it "prints the n/a headline alone for an error-dominated run" do
      results = [result(add, :killed), result(add, :error, to: "< 1", reason: "boom"),
                 result(add, :error, to: "== 1", reason: "bam")]
      text = render(honest_report(results), color: :never)
      expect(text).to include("Score: n/a (1 of 3 mutants scored, 100.0 % of scored)")
      expect(text).not_to include("killed, tested subjects")
    end

    it "prints the verbose score split only when something was tested" do
      text = render(honest_report([], wall: 0), color: :never, verbose: true)
      expect(text).to include("Score: n/a")
      expect(text).not_to include("(killed+timeout)")
    end

    it "echoes the threshold with a nil score, without breaking" do
      text = render(honest_report([], wall: 0), color: :never, threshold: 80)
      expect(text).to include("Score: n/a · threshold 80 - nothing tested")
      expect(text).to include("saboteur: no mutants in 0s - score n/a (threshold 80)")
    end

    it "paints a score at its threshold green, without a break" do
      headline = render(honest_report([result(add, :killed)]), color: :always, threshold: 100)
                 .lines.find { |line| line.start_with?("Score: ") }
      expect(headline).to include("\e[32m100.0%\e[0m")
      expect(headline).not_to include("(break)")
    end

    it "prints no below-threshold reason at or above the threshold" do
      surviving = [result(add, :killed), result(add, :survived, to: "< 1")]
      expect(verdict_line_for(honest_report(surviving), 1, threshold: 50)).to eq("\u2717 exit 1 - 1 survivor\n")
      three_quarters = [result(add, :killed), result(add, :killed, to: "< 1"),
                        result(add, :killed, to: "== 1"), result(add, :survived, to: "!= 1")]
      expect(verdict_line_for(honest_report(three_quarters), 1, threshold: 50))
        .to eq("\u2717 exit 1 - 1 survivor\n")
    end

    it "names gate limits when an exit 1 has no other reason" do
      expect(verdict_line_for(honest_report([result(add, :killed)]), 1))
        .to eq("\u2717 exit 1 - gate limits exceeded\n")
    end

    it "names an error-dominated run on exit 3" do
      results = [result(add, :killed), result(add, :error, to: "< 1", reason: "boom"),
                 result(add, :error, to: "== 1", reason: "bam")]
      expect(verdict_line_for(honest_report(results), 3))
        .to eq("\u2717 exit 3 - most executed mutants errored; the run tested almost nothing\n")
    end

    it "prints the generic incomplete verdict for an ordinary partial run" do
      expect(verdict_line_for(honest_report([result(add, :killed)]), 3))
        .to eq("\u2717 exit 3 - run incomplete; the score is not a verified result\n")
    end

    it "does not cry unverifiable outside review mode" do
      report = honest_report([], skipped: { add => "no coverage" })
      expect(verdict_line_for(report, 3))
        .to eq("\u2717 exit 3 - run incomplete; the score is not a verified result\n")
    end

    it "does not cry unverifiable when a subject under review has results" do
      report = honest_report([result(add, :killed)], skipped: { shipping => "no coverage" },
                                                     subjects: [add, shipping], review: true)
      expect(verdict_line_for(report, 3))
        .to eq("\u2717 exit 3 - run incomplete; the score is not a verified result\n")
    end

    it "dedupes the joined skip reasons" do
      skipped = { add => "no coverage", shipping => "no coverage" }
      report = honest_report([], skipped:, subjects: [add, shipping], review: true)
      expect(verdict_line_for(report, 3))
        .to eq("\u2717 exit 3 - 2 changes could not be verified (no coverage)\n")
    end

    it "names errors and rejected kills with exact plurals" do
      errors = [result(add, :killed), result(add, :error, to: "< 1", reason: "boom"),
                result(add, :error, to: "== 1", reason: "bam")]
      expect(canonical(errors)).to include("2 errors")
      rejected = [result(add, :error, to: "< 1", reason: "boom", rejected_kill: true),
                  result(add, :error, to: "== 1", reason: "bam", rejected_kill: true)]
      expect(canonical(rejected)).to include("2 errors (2 rejected kills)")
      one = [result(add, :error, to: "< 1", reason: "boom", rejected_kill: true)]
      expect(canonical(one)).to include("1 error (1 rejected kill)")
      expect(canonical([result(add, :error, to: "< 1", reason: "boom")])).not_to include("rejected")
    end
    it "prints no break when the score is above the threshold" do
      headline = render(honest_report([result(add, :killed)]), color: :never, threshold: 80)
                 .lines.find { |line| line.start_with?("Score: ") }
      expect(headline).to include("100.0% · threshold 80")
      expect(headline).not_to include("(break)")
    end

    it "breaks just below a fractional threshold, painted red, and says so in the verdict" do
      results = [result(add, :killed), result(add, :killed, to: "< 1"),
                 result(add, :killed, to: "== 1"), result(add, :survived, to: "!= 1")]
      text = render(honest_report(results), color: :always, exit_code: 1, threshold: 75.5)
      headline = text.lines.find { |line| line.start_with?("Score: ") }
      expect(headline).to include("\e[31;1m75.0%\e[0m")
      expect(headline).to include("(break)")
      expect(text.lines.find { |line| line.include?("\u2717") })
        .to eq("\e[31;1m\u2717 exit 1 - score 75.0% below threshold 75.5, 1 survivor\e[0m\n")
    end

    it "names an all-unreachable run on exit 3" do
      results = [result(add, :unreachable, to: "< 1"), result(add, :unreachable, to: "== 1")]
      expect(verdict_line_for(honest_report(results), 3))
        .to eq("\u2717 exit 3 - the change could not be verified (all mutants unreachable)\n")
    end

    it "names a stop before any mutant was tested on exit 3" do
      stop = Saboteur::EarlyStop.new(reason: "signal", unreached: [], truncated: [], unverified: [])
      expect(verdict_line_for(honest_report([], early_stop: stop), 3))
        .to eq("\u2717 exit 3 - stopped before any mutant was tested; there is no score to judge\n")
    end

    it "prints the generic incomplete verdict when a stopped run still tested mutants" do
      stop = Saboteur::EarlyStop.new(reason: "signal", unreached: [], truncated: [], unverified: [])
      expect(verdict_line_for(honest_report([result(add, :killed)], early_stop: stop), 3))
        .to eq("\u2717 exit 3 - run incomplete; the score is not a verified result\n")
    end

    it "does not cry unverifiable over an empty subject list under review" do
      expect(verdict_line_for(honest_report([], subjects: [], review: true), 3))
        .to eq("\u2717 exit 3 - run incomplete; the score is not a verified result\n")
    end
    it "does not call a mixed run all-unreachable" do
      results = [result(add, :unreachable, to: "< 1"), result(add, :killed, to: "== 1")]
      expect(verdict_line_for(honest_report(results), 3))
        .to eq("\u2717 exit 3 - run incomplete; the score is not a verified result\n")
    end
    it "says 1 subject not scored in the singular" do
      skipped = { cart.fetch("Cart#total") => "no coverage" }
      text = render(honest_report([result(add, :killed)], skipped:, subjects:), color: :never)
      expect(text).to include("1 subject not scored - no test executes it")
      expect(text).not_to include("1 subjects")
    end

    it "names gate limits when the score is nil under a threshold" do
      report = honest_report([], wall: 0)
      expect(verdict_line_for(report, 1, threshold: 80))
        .to eq("\u2717 exit 1 - gate limits exceeded\n")
    end
  end
end
