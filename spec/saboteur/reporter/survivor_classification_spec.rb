# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Survivor classification labels (#192): why a survivor is worth looking at,
# as a label only - scores and the exit code never change.
RSpec.describe Saboteur::Reporter::SurvivorClassification do
  def survivor_for(source, from:, to:, covered_by: ["spec/a_spec.rb:1"], coarse: false, operator: "test")
    survivor_for_edits(source, [[from, to]], covered_by: covered_by, coarse: coarse, operator: operator)
  end

  def survivor_for_edits(source, pairs, covered_by: ["spec/a_spec.rb:1"], coarse: false, operator: "test")
    dir = Dir.mktmpdir("saboteur-classify-")
    path = File.join(dir, "target.rb")
    File.write(path, source)
    subject = Saboteur::SubjectFinder.new.call(path).subjects.first
    edits = pairs.map do |from, to|
      at = subject.file_source.b.index(from.b)
      Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at,
                                         end_byte: at + from.bytesize, replacement: to)
    end
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: operator,
                                                      edits: edits, coarse: coarse)
    Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                               mutated_source: subject.apply(mutation.edits), covered_by: covered_by)
  end

  it "labels a covered survivor with the fallback kind when no rule matches" do
    result = survivor_for("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n", from: ">=", to: ">")
    expect(described_class.label(result)).to eq("result unchecked")
  end

  # One pin per gap kind (D2): the kind names what sort of check is
  # missing, from the operator and the edit shape only.
  {
    "comparison" => ["boundary", "class A\n  def adult?(age)\n    age >= 18\n  end\nend\n", ">=", ">"],
    "condition_negation" => ["branch", "class A\n  def go(c)\n    m if c\n  end\nend\n", "if c", "unless c"],
    "statement_removal" => ["effect", "class A\n  def go\n    call\n  end\nend\n", "call", "nil"],
    "literal_number" => ["number", "class A\n  def n\n    41\n  end\nend\n", "41", "42"],
    "rescue_removal" => ["error path", "class A\n  def go\n    m\n  rescue\n    nil\n  end\nend\n",
                         "rescue\n    nil", "nil"],
    "body_nil" => ["result unchecked", "class A\n  def n\n    41\n  end\nend\n", "41", "nil"]
  }.each do |operator, (kind, source, from, to)|
    it "labels a #{operator} survivor as #{kind}" do
      expect(described_class.label(survivor_for(source, from: from, to: to, operator: operator))).to eq(kind)
    end
  end

  it "labels operand_replacement on a comparison as boundary, from the edit shape" do
    result = survivor_for("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n",
                          from: "age >= 18", to: "age", operator: "operand_replacement")
    expect(described_class.label(result)).to eq("boundary")
  end

  it "labels operand_replacement on arithmetic as result unchecked" do
    result = survivor_for("class A\n  def total(a, b)\n    a + b\n  end\nend\n",
                          from: "a + b", to: "a", operator: "operand_replacement")
    expect(described_class.label(result)).to eq("result unchecked")
  end

  # The comparison probe must read only the edited bytes: a comparison
  # elsewhere in the file says nothing about this mutation's shape.
  # The slice is exclusive of the edit's end byte: an inclusive slice would
  # pull in the next character and misread "x+1" next to ">" as a comparison.
  it "reads exactly the edited bytes, not the byte after them" do
    source = "class A\n  def calc(x)\n    x+1>2\n  end\nend\n"
    result = survivor_for(source, from: "x+1", to: "x", operator: "operand_replacement")
    expect(described_class.label(result)).to eq("result unchecked")
  end

  it "ignores a comparison outside the edited bytes" do
    source = "class A\n  def check(age, total)\n    age >= 18 && total > 0 ? total : total + 1\n  end\nend\n"
    result = survivor_for(source, from: "total + 1", to: "total", operator: "operand_replacement")
    expect(described_class.label(result)).to eq("result unchecked")
  end

  # Several edits, only one a comparison: any single comparison edit is
  # enough to call the mutation a boundary change.
  it "calls a multi-edit mutation boundary when any one edit is a comparison" do
    source = "class A\n  def greet(name, age)\n    name if age >= 18\n  end\nend\n"
    result = survivor_for_edits(source, [["name", "nom"], ["age >= 18", "age"]],
                                operator: "operand_replacement")
    expect(described_class.label(result)).to eq("boundary")
  end

  # An edit range outside the file bytes slices to nil; the probe must read
  # that as "not a comparison", not crash.
  it "reads an out-of-file edit range as no comparison" do
    result = survivor_for("class A\n  def total(a, b)\n    a + b\n  end\nend\n",
                          from: "a + b", to: "a", operator: "operand_replacement")
    size = result.subject.file_source.bytesize
    edit = Saboteur::MutationSource::Edit.new(file: result.subject.file, start_byte: size + 10,
                                              end_byte: size + 12, replacement: "x")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: result.subject.id,
                                                      operator: "operand_replacement",
                                                      edits: [edit], coarse: false)
    out_of_file = Saboteur::MutantResult.new(subject: result.subject, mutation:,
                                             status: :survived, mutated_source: result.mutated_source,
                                             covered_by: ["spec/a_spec.rb:1"])
    expect(described_class.send(:comparison_edit?, out_of_file)).to be(false)
  end

  it "maps every built-in operator to a kind exactly once, with no fallthrough" do
    covered = Saboteur::Reporter::GapKinds::BY_OPERATOR.keys + Saboteur::Reporter::GapKinds::SHAPE_DECIDED
    expect(covered.tally.values).to all(eq(1))
    expect(covered.sort).to eq(Saboteur::MutationSource::OperatorRegistry::DESCRIPTIONS.keys.sort)
  end

  it "treats an operator missing from the table as result unchecked" do
    result = survivor_for("class A\n  def n\n    41\n  end\nend\n", from: "41", to: "42",
                                                                    operator: "future_operator")
    expect(described_class.label(result)).to eq("result unchecked")
  end

  it "labels a bytecode-identical mutant as likely equivalent, before the gap kind" do
    result = survivor_for("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n", from: "18", to: "18")
    expect(described_class.label(result)).to eq("likely_equivalent")
  end

  it "labels an exception message edit as arid: raise, fail and warn (#1066)" do
    %w[raise fail warn].each do |call|
      source = "class A\n  def go\n    #{call} \"boom\"\n  end\nend\n"
      result = survivor_for(source, from: '"boom"', to: '""')
      expect(described_class.label(result)).to eq("arid"), "expected #{call} message edit to be arid"
    end
  end

  it "does not label a non-diagnostic string edit as arid" do
    result = survivor_for("class A\n  def go\n    register \"boom\"\n  end\nend\n",
                          from: '"boom"', to: '""')
    expect(described_class.label(result)).not_to eq("arid")
  end

  # The patterns match whole lines, so every edit on a modifier-if raise
  # line reads as arid - the condition's mutants included (#1066).
  it "labels a condition edit on a modifier-if raise line as arid" do
    result = survivor_for("class A\n  def go(c)\n    raise \"boom\" if c\n  end\nend\n",
                          from: "if c", to: "unless c")
    expect(described_class.label(result)).to eq("arid")
  end

  # A bare re-raise in a rescue body is an arid line too: removing the
  # statement (statement_removal) labels arid like any raise line.
  it "labels the removal of a bare re-raise in a rescue body as arid" do
    result = survivor_for("class A\n  def go\n    go\n  rescue StandardError\n    raise\n  end\nend\n",
                          from: "raise", to: "nil")
    expect(described_class.label(result)).to eq("arid")
  end

  it "labels a survivor on an arid line as arid, before the gap kind" do
    result = survivor_for("class A\n  def tell(msg)\n    puts msg\n  end\nend\n", from: "puts msg", to: "nil")
    expect(described_class.label(result)).to eq("arid")
  end

  it "labels an uncovered survivor with no signal as input_gap" do
    result = survivor_for("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n", from: ">=", to: ">",
                                                                                     covered_by: [])
    expect(described_class.label(result)).to eq("input_gap")
  end

  # D6 ladder pin: covered -> gap kind, uncovered -> input_gap, coarse -> nil,
  # and the external runner's pseudo id keeps its tool_limit precedence (#305).
  it "pins the covered/uncovered/coarse ladder with the pseudo-id precedence" do
    source = "class A\n  def adult?(age)\n    age >= 18\n  end\nend\n"
    covered = survivor_for(source, from: ">=", to: ">", operator: "comparison")
    uncovered = survivor_for(source, from: ">=", to: ">", covered_by: [])
    coarse = survivor_for(source, from: ">=", to: ">", covered_by: [], coarse: true)
    pseudo = survivor_for(source, from: ">=", to: ">",
                                  covered_by: [Saboteur::Execution::ExternalRunner::PSEUDO_TEST])
    expect(described_class.label(covered)).to eq("boundary")
    expect(described_class.label(uncovered)).to eq("input_gap")
    expect(described_class.label(coarse)).to be_nil
    expect(described_class.label(pseudo)).to eq("tool_limit")
  end

  it "labels a survivor observed only by the external runner's pseudo id as tool_limit (#1071)" do
    result = survivor_for("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n", from: ">=", to: ">",
                                                                                     covered_by: [Saboteur::Execution::ExternalRunner::PSEUDO_TEST])
    expect(described_class.label(result)).to eq("tool_limit")
  end

  it "labels a survivor with a gap kind when real coverage sits next to the pseudo id (#305)" do
    covered = [Saboteur::Execution::ExternalRunner::PSEUDO_TEST, "spec/a_spec.rb:1"]
    result = survivor_for("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n", from: ">=", to: ">",
                                                                                     covered_by: covered)
    expect(described_class.label(result)).to eq("result unchecked")
  end

  it "withholds a gap kind from coarse mutants: their covering list is a planned guess" do
    result = survivor_for("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n",
                          from: ">=", to: ">", coarse: true)
    expect(described_class.label(result)).to be_nil
  end

  # Removing a logging statement is arid whatever removed it: line text
  # only catches the first line, so the enclosing call decides (#665).
  it "labels an edit that removes a whole multi-line logging call as arid" do
    result = survivor_for("class A\n  def tell(msg)\n    logger.info(\n      msg)\n  end\nend\n",
                          from: "logger.info(\n      msg)", to: "nil", covered_by: [])
    expect(described_class.label(result)).to eq("arid")
  end

  it "does not label an edit arid when it spans a logging call and following code" do
    result = survivor_for("class A\n  def tell(msg)\n    logger.info(msg)\n    msg\n  end\nend\n",
                          from: "logger.info(msg)\n    msg", to: "nil", covered_by: [])
    expect(described_class.label(result)).to eq("input_gap")
  end

  it "labels a chained logger call as arid (#665)" do
    result = survivor_for("class A\n  def tell\n    Sentry.sdk_logger.error(\"x\")\n  end\nend\n",
                          from: "Sentry.sdk_logger.error(\"x\")", to: "nil", covered_by: [])
    expect(described_class.label(result)).to eq("arid")
  end

  # The sentry-ruby case: the lazy message inside a warn do..end block
  # starts with the string, not the logger, so only the enclosing call
  # reads as arid.
  it "labels an edit inside a chained logger's block as arid, from the enclosing call (#665)" do
    message = "\"skip \#{job}\""
    source = <<~RUBY
      class A
        def watch(job)
          Sentry.sdk_logger.warn(Sentry::LOGGER_PROGNAME) do
            #{message}
          end
        end
      end
    RUBY
    result = survivor_for(source, from: message, to: '"skip"')
    expect(described_class.label(result)).to eq("arid")
  end

  # The sentry-ruby line-60 case: the edit sits inside a NESTED call
  # (job.source_location&.join) within the logger block. The smallest
  # enclosing call is the nested one, so the label must walk out to the
  # logger call (#665).
  it "labels a safe-navigation edit inside a nested call in a logger block as arid (#665)" do
    message = "\"at \#{job.source_location&.join(\":\")}\""
    source = <<~RUBY
      class A
        def watch(job)
          Sentry.sdk_logger.warn(Sentry::LOGGER_PROGNAME) do
            #{message}
          end
        end
      end
    RUBY
    result = survivor_for(source, from: "&.", to: ".", covered_by: [])
    expect(described_class.label(result)).to eq("arid")
  end

  it "labels an argument removal inside a nested call in a logger block as arid (#665)" do
    message = "\"at \#{job.source_location&.join(\":\")}\""
    source = <<~RUBY
      class A
        def watch(job)
          Sentry.sdk_logger.warn(Sentry::LOGGER_PROGNAME) do
            #{message}
          end
        end
      end
    RUBY
    result = survivor_for(source, from: '":"', to: "", covered_by: [])
    expect(described_class.label(result)).to eq("arid")
  end

  # The whole-slice match let a logger SIBLING inside a block swallow an
  # unrelated edit: the outer items.each slice contains ".instrument", so
  # the paid? edit read as arid (#665 security probe). Only the call's
  # head - receiver, operator, message - may match.
  it "does not label an edit arid for a logger sibling inside the same block (#665)" do
    source = <<~RUBY
      class A
        def charge_all(items)
          items.each do |x|
            tracer.instrument(x)
            charge!(x) if x.paid?
          end
        end
      end
    RUBY
    result = survivor_for(source, from: "paid?", to: "!paid?", covered_by: [])
    expect(described_class.label(result)).to eq("input_gap")
  end

  # Each boundary term of call_head's || chain decides a shape the others
  # miss; a pattern in the arguments must never reach the head (#665).
  it "stops the head at the opening paren when the arguments mention a logger (#665)" do
    source = <<~RUBY
      class A
        def charge_all(items)
          notify("tracer.instrument span") do |x|
            charge!(x) if x.paid?
          end
        end
      end
    RUBY
    result = survivor_for(source, from: "paid?", to: "!paid?", covered_by: [])
    expect(described_class.label(result)).to eq("input_gap")
  end

  it "stops the head at the first argument of a multi-argument call without parens (#665)" do
    source = <<~RUBY
      class A
        def charge_all(items)
          notify "tracer.instrument span", items do |x|
            charge!(x) if x.paid?
          end
        end
      end
    RUBY
    result = survivor_for(source, from: "paid?", to: "!paid?", covered_by: [])
    expect(described_class.label(result)).to eq("input_gap")
  end

  it "stops the head at the first argument when the call has no parens (#665)" do
    source = <<~RUBY
      class A
        def charge_all(items)
          notify_result "tracer.instrument span" do |x|
            charge!(x) if x.paid?
          end
        end
      end
    RUBY
    result = survivor_for(source, from: "paid?", to: "!paid?", covered_by: [])
    expect(described_class.label(result)).to eq("input_gap")
  end

  # operand_replacement on the head length must not let the whole slice
  # back in: the pattern sits inside the arguments, before the file
  # offset the mutant would cut at (#665).
  it "never matches arguments that sit within the mutant's cut (#665)" do
    source = <<~RUBY
      class A
        def charge_all(items)
          result = wrap_call(tracer.instrument, items) do |x|
            charge!(x) if x.paid?
          end
        end
      end
    RUBY
    result = survivor_for(source, from: "paid?", to: "!paid?", covered_by: [])
    expect(described_class.label(result)).to eq("input_gap")
  end

  # call_head's contract, pinned directly: the boundary terms decide which
  # call shapes stop where (#665).
  it "cuts the head at the opening paren (#665)" do
    call = Prism.parse("notify(x) do\ny\nend\n").value.statements.body.first
    expect(described_class.send(:call_head, call)).to eq("notify")
  end

  it "cuts the head at the first argument without parens (#665)" do
    call = Prism.parse("notify x, y do\nz\nend\n").value.statements.body.first
    expect(described_class.send(:call_head, call)).to eq("notify")
  end

  it "cuts the head at a bare block keyword (#665)" do
    call = Prism.parse("warn do\nx\nend\n").value.statements.body.first
    expect(described_class.send(:call_head, call)).to eq("warn")
  end

  it "keeps the whole slice for an argument-free call (#665)" do
    call = Prism.parse("foo.bar\n").value.statements.body.first
    expect(described_class.send(:call_head, call)).to eq("foo.bar")
  end

  it "does not label a nested-call edit arid when the outer call is not arid (#665)" do
    message = "\"at \#{job.source_location&.join(\":\")}\""
    source = <<~RUBY
      class A
        def watch(job)
          transform(job) do
            #{message}
          end
        end
      end
    RUBY
    result = survivor_for(source, from: "&.", to: ".", covered_by: [])
    expect(described_class.label(result)).to eq("input_gap")
  end

  it "does not label an edit inside a non-arid call's block as arid" do
    message = "\"skip \#{job}\""
    source = <<~RUBY
      class A
        def watch(job)
          transform(job) do
            #{message}
          end
        end
      end
    RUBY
    result = survivor_for(source, from: message, to: '"skip"', covered_by: [])
    expect(described_class.label(result)).to eq("input_gap")
  end

  # A file the parser cannot read must not classify from a broken tree.
  it "treats an edit in an unparseable file as not arid (#665)" do
    tree = Prism.parse("puts x\ndef broken(\n")
    expect(tree.success?).to be(false)
    edit = Saboteur::MutationSource::Edit.new(file: "x.rb", start_byte: 0, end_byte: 3, replacement: "")
    expect(described_class.send(:inside_arid_call?, tree, edit, [/\Aputs/])).to be(false)
  end

  # The containment guard in enclosing_calls, both sides: an edit that
  # reaches outside the call is not swallowed by it.
  it "refuses an edit that starts before the call (#665)" do
    call = Prism.parse("alpha\nbeta(gamma)\n").value.statements.body[1]
    expect(described_class.send(:enclosing_calls, call, 0, 8)).to eq([])
  end

  it "refuses an edit that ends after the call (#665)" do
    call = Prism.parse("beta(gamma)\nomega\n").value.statements.body[0]
    expect(described_class.send(:enclosing_calls, call, 1, 15)).to eq([])
  end

  it "collects every call swallowing the edit, outermost first (#665)" do
    program = Prism.parse("alpha(beta(gamma))\n").value
    outer = program.statements.body[0]
    inner = outer.arguments.arguments[0]
    expect(described_class.send(:enclosing_calls, program, 6, 10)).to eq([outer, inner])
  end

  it "labels an edit arid when every line it touches is arid" do
    result = survivor_for("class A\n  def tell(a, b)\n    puts a\n    puts b\n  end\nend\n",
                          from: "puts a\n    puts b", to: "nil", covered_by: [])
    expect(described_class.label(result)).to eq("arid")
  end

  it "accepts a nondefault arid hint list" do
    result = survivor_for("class A\n  def tell(msg)\n    audit_log msg\n  end\nend\n",
                          from: "audit_log msg", to: "nil", covered_by: [])
    expect(described_class.label(result)).to eq("input_gap")
    expect(described_class.label(result, arid: ["audit_log"])).to eq("arid")
  end

  it "locates the edited line by bytes with multibyte text before and on the line" do
    result = survivor_for("class A\n  # caf\u00e9 menu\n  def tell(msg)\n    puts \"caf\u00e9 \#{msg}\"\n  end\nend\n",
                          from: "puts", to: "nil", covered_by: [])
    expect(described_class.label(result)).to eq("arid")
  end

  it "splices several edits from the end of the def back, however they are ordered" do
    # Both edits change length and compile to the original's instructions;
    # applied in the wrong order the second splice lands on stale offsets.
    result = survivor_for_edits("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n",
                                [["age >=", "(age) >="], ["18", "0x12"]])
    expect(described_class.label(result)).to eq("likely_equivalent")
  end

  it "sorts edits before splicing: unsorted edits must not land on stale offsets" do
    # argument_removal/pair_removal emit [argument, comma] with the comma
    # BEFORE the argument when the last one goes - unsorted by start_byte.
    # Without the sort the reversed splices run early-to-late and the
    # second lands two bytes off, mangling bytecode-identical code.
    result = survivor_for_edits("class A\n  def old?(age)\n    age >= 18 && age < 65\n  end\nend\n",
                                [["< 65", "< (65)"], ["18", "(18)"]])
    expect(described_class.label(result)).to eq("likely_equivalent")
  end

  it "reads the line an edit reaches into through its final byte" do
    # The edit ends on the "b" that opens the bar line: end_byte - 1 is
    # that "b", so the line search must start there and include the rest
    # of the bar line. One byte earlier finds the newline inside the edit
    # and drops the bar line entirely.
    result = survivor_for("class A\n  def m\nfoo\nbar\n  end\nend\n",
                          from: "foo\nb", to: "nil")
    expect(described_class.label(result, arid: ["\\Afoo\\z"])).to eq("result unchecked")
  end

  it "compiles with the subject's frozen-string-literal setting" do
    result = survivor_for("# frozen_string_literal: true\nclass A\n  def tell(msg)\n    puts msg\n  end\nend\n",
                          from: "puts msg", to: "nil")
    checker = Saboteur::Engine::BytecodeEquivalence.new
    allow(Saboteur::Engine::BytecodeEquivalence).to receive(:new).and_return(checker)
    expect(checker).to receive(:equivalent?).with(anything, anything, frozen_string_literal: true)
                                            .and_call_original
    described_class.label(result)
  end

  it "is not arid when any one edit of several is off an arid line" do
    result = survivor_for_edits("class A\n  def m(a)\n    puts a\n    a >= 18\n  end\nend\n",
                                [["puts a", "nil"], [">=", ">"]], covered_by: [])
    expect(described_class.label(result)).to eq("input_gap")
  end

  it "is not arid for a zero-width edit on a blank line" do
    source = "class A\n  def m(a)\n\n    puts a\n  end\nend\n"
    dir = Dir.mktmpdir("saboteur-classify-")
    path = File.join(dir, "target.rb")
    File.write(path, source)
    subject = Saboteur::SubjectFinder.new.call(path).subjects.first
    at = source.b.index("\n\n") + 1
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: at,
                                              end_byte: at, replacement: "x")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                      edits: [edit], coarse: false)
    result = Saboteur::MutantResult.new(subject:, mutation:, status: :survived,
                                        mutated_source: subject.apply(mutation.edits), covered_by: [])
    expect(described_class.label(result)).to eq("input_gap")
  end

  it "extracts the edited line when nothing precedes it, not even a newline" do
    # A one-line class: the edit sits on the file's first and only line.
    result = survivor_for("class A; def m; puts a; end; end\n",
                          from: "puts a", to: "nil", covered_by: [])
    expect(described_class.label(result, arid: ["\\Aclass A; def m; puts a; end; end\\z"])).to eq("arid")
  end

  it "extracts the edited line at the end of a file without a trailing newline" do
    # The edit ends on the file's LAST line (the def's own end, the class
    # end sharing the line) and the file has no trailing newline, so the
    # bytesize fallback is what finds the line end.
    result = survivor_for("class A\n  def m\n    puts a\n  end end",
                          from: "puts a\n  end", to: "nil", covered_by: [])
    expect(described_class.label(result, arid: ["\\Aputs a\\z", "\\Aend end\\z"])).to eq("arid")
  end

  it "reads only the edited lines when the edit ends at the newline" do
    result = survivor_for("class A\n  def m(a)\n    puts a\n    a >= 18\n  end\nend\n",
                          from: "puts a\n", to: "nil", covered_by: [])
    expect(described_class.label(result)).to eq("arid")
  end

  it "reads every line an edit reaches into" do
    result = survivor_for("class A\n  def m(a)\n    puts a\n    a >= 18\n  end\nend\n",
                          from: "puts a\n    a", to: "nil", covered_by: [])
    expect(described_class.label(result)).to eq("input_gap")
  end

  it "matches multibyte arid patterns against the decoded line" do
    result = survivor_for("class A\n  def tell\n    note \"caf\u00e9\"\n  end\nend\n",
                          from: "note", to: "nil", covered_by: [])
    expect(described_class.label(result, arid: ['\Anote "caf\u00e9"'])).to eq("arid")
  end

  it "scrubs an invalid byte sequence on the edited line instead of raising" do
    edit = Saboteur::MutationSource::Edit.new(file: "x.rb", start_byte: 0, end_byte: 4,
                                              replacement: "nil")
    subject = instance_double(Saboteur::Subject, file_source: "puts a # caf\xC3".b)
    lines = described_class.send(:edited_lines, subject, edit)
    expect(lines).to eq(["puts a # caf\uFFFD"])
    expect(lines.first.valid_encoding?).to be(true)
  end

  it "never labels a non-survivor" do
    result = survivor_for("class A\n  def adult?(age)\n    age >= 18\n  end\nend\n", from: ">=", to: ">")
    killed = Saboteur::MutantResult.new(subject: result.subject, mutation: result.mutation,
                                        status: :killed, mutated_source: result.mutated_source)
    expect(described_class.label(killed)).to be_nil
  end
end
