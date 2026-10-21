# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::MutationSource::Builtin do
  def mutations(body, params: "(a, b)")
    subject = subjects_in("class K\n  def m#{params}\n#{body}\n  end\nend\n").first
    mutated_texts(subject).map { |operator, text| [operator, text.lines[1..-2].join.strip] }
  end

  def texts(body, operator, **)
    mutations(body, **).select { |op, _| op == operator }.map(&:last)
  end

  describe "binary shape" do
    it "gives no comparison or arithmetic mutants to the explicit-receiver spelling" do
      expect(texts("    a.+(b)", "arithmetic")).to be_empty
      expect(texts("    a.==(b)", "comparison")).to be_empty
    end
  end

  describe "identity" do
    it "is the builtin source and labels its own mutations with that name" do
      subject = subjects_in("class K\n  def m(a)\n    a >= 1\n  end\nend\n").first
      source = described_class.new(operators: ["comparison"])
      expect(source.name).to eq("builtin")
      expect(source.mutations_for(subject).map(&:source).uniq).to eq(["builtin"])
    end
  end

  describe "operator wiring" do
    it "wires arid into regex_replacement too" do
      regex = subjects_in("class K\n  def m(input)\n    input =~ /\A\d+\z/\n  end\nend\n").first
      expect(described_class.new(operators: ["regex_replacement"]).mutations_for(regex)).not_to be_empty
      expect(described_class.new(operators: ["regex_replacement"], arid: ["input"]).mutations_for(regex)).to be_empty
    end

    it "wires arid into method_swap and interpolation_removal too" do
      swap = subjects_in("class K\n  def m(xs)\n    xs.min { |x| x }\n  end\nend\n").first
      expect(described_class.new(operators: ["method_swap"], arid: ["min"]).mutations_for(swap)).to be_empty
      interp = subjects_in(%(class K\n  def m(name)\n    "Hello, \#{name}!"\n  end\nend\n)).first
      expect(described_class.new(operators: ["interpolation_removal"], arid: ["name"])
        .mutations_for(interp)).to be_empty
    end
  end

  describe "coarse" do
    it "replaces the body with nil and with raise, before anything else" do
      found = mutations("    a >= b")
      expect(found.first(2)).to eq([%w[body_nil nil], %w[body_raise raise]])
    end

    it "marks only body replacements as coarse" do
      subject = subjects_in("class K\n  def m(a)\n    a + 1\n  end\nend\n").first
      coarse = described_class.new.mutations_for(subject).select(&:coarse).map(&:operator)
      expect(coarse).to eq(%w[body_nil body_raise])
    end

    it "does not replace a body that is already nil, or that is only arid statements" do
      expect(texts("    nil", "body_nil")).to be_empty
      expect(texts("    puts a\n    logger.info(b)", "body_nil")).to be_empty
    end

    it "replaces a body that does real work before an arid last line" do
      expect(texts("    a = b + 1\n    puts a", "body_nil")).to eq(["nil"])
    end

    it "does not raise inside a body whose rescue catches it (the stop would hide every fine mutant)" do
      ["rescue", "rescue => e", "rescue StandardError", "rescue Exception => e"].each do |clause|
        clause = clause.tr("\\", "")
        subject = subjects_in("class K\n  def m\n    work\n  #{clause}\n    1\n  end\nend\n").first
        expect(mutated_texts(subject).map(&:first)).not_to include("body_raise"), clause
      end
    end

    it "does not raise inside a body whose rescue lists a catch-all beside a specific error" do
      subject = subjects_in("class K\n  def m\n    work\n  rescue ArgumentError, Exception\n    1\n  end\nend\n").first
      expect(mutated_texts(subject).map(&:first)).not_to include("body_raise")
    end

    it "still raises inside a body whose rescue catches only specific errors" do
      subject = subjects_in("class K\n  def m\n    work\n  rescue ArgumentError\n    1\n  end\nend\n").first
      expect(mutated_texts(subject).map(&:first)).to include("body_raise")
    end

    it "keeps rescue clauses when replacing the body" do
      subject = subjects_in("class K\n  def m\n    work\n  rescue StandardError\n    1\n  end\nend\n").first
      text = mutated_texts(subject).to_h.fetch("body_nil")
      expect(text).to eq("def m\n    nil\n  rescue StandardError\n    1\n  end")
    end

    it "replaces a predicate method's body with true and with false, instead of nil" do
      subject = subjects_in("class K\n  def ok?\n    @a > 1\n  end\nend\n").first
      coarse = described_class.new.mutations_for(subject).select(&:coarse)
      expect(coarse.map(&:operator)).to eq(%w[body_true body_false body_raise])
      expect(coarse.map { |m| subject.apply(m.edits) }.first).to eq("def ok?\n    true\n  end")
    end

    it "handles endless defs" do
      subject = subjects_in("class K\n  def m = 1 + 2\nend\n").first
      expect(mutated_texts(subject).first).to eq(["body_nil", "def m = nil"])
    end

    it "generates nothing for an empty method" do
      expect(mutations("", params: "")).to be_empty
    end
  end

  describe "comparison" do
    # The sufficient relational set (Kaminski et al. 2011): the other
    # replacements are subsumed. For == and != Ruby gets true/false, not
    # <=/>=, which raise NoMethodError on objects that are not Comparable.
    it "uses the sufficient replacements for each comparison" do
      expect(texts("    a < b", "comparison")).to eq(["a <= b", "a != b", "false"])
      expect(texts("    a <= b", "comparison")).to eq(["a < b", "a == b", "true"])
      expect(texts("    a > b", "comparison")).to eq(["a >= b", "a != b", "false"])
      expect(texts("    a >= b", "comparison")).to eq(["a > b", "a == b", "true"])
      expect(texts("    a == b", "comparison")).to eq(%w[false true])
      expect(texts("    a != b", "comparison")).to eq(%w[true false])
    end

    it "no longer emits the subsumed direction swap (< to >)" do
      expect(texts("    a < b", "comparison")).not_to include("a > b")
    end
  end

  describe "boolean logic" do
    # The sufficient connector set (Just et al. 2012): each operand alone,
    # plus the constant the connector cannot produce. The swap is subsumed.
    it "replaces && and || with each operand and with the absorbing constant" do
      expect(texts("    x = a && b", "boolean_logic")).to eq(["x = a", "x = b", "x = false"])
      expect(texts("    x = opts[:k] || default", "boolean_logic"))
        .to eq(["x = opts[:k]", "x = default", "x = true"])
      expect(texts("    a or b", "boolean_logic")).to eq(%w[a b true])
    end

    it "keeps an operand's own parentheses and always produces valid Ruby" do
      expect(texts("    x = a && (b || c)", "boolean_logic")).to include("x = (b || c)")
      expect(texts("    x = a && b ? 1 : 2", "boolean_logic")).to all(satisfy { |t|
        Prism.parse("def m\n#{t}\nend").success?
      })
    end

    it "removes negation" do
      expect(texts("    !a.empty?", "negation_removal")).to eq(["a.empty?"])
    end

    it "replaces if/unless/ternary conditions with true and false" do
      expect(texts("    return 1 if a > b", "condition_true")).to eq(["return 1 if true"])
      expect(texts("    a ? 1 : 2", "condition_false")).to eq(["false ? 1 : 2"])
      expect(texts("    unless a\n      1\n    end", "condition_true")).to eq(["unless true\n      1\n    end"])
    end

    it "skips the loop condition replacement that can never end the loop" do
      expect(texts("    while a\n      b\n    end", "condition_true")).to be_empty
      expect(texts("    while a\n      b\n    end", "condition_false")).to eq(["while false\n      b\n    end"])
      expect(texts("    until a\n      b\n    end", "condition_false")).to be_empty
      expect(texts("    until a\n      b\n    end", "condition_true")).to eq(["until true\n      b\n    end"])
    end
  end

  describe "arithmetic" do
    it "swaps + with - and * with /" do
      expect(texts("    a + b", "arithmetic")).to eq(["a - b"])
      expect(texts("    a * b", "arithmetic")).to eq(["a / b"])
    end

    it "leaves string concatenation alone" do
      expect(texts('    "x" + b', "arithmetic")).to be_empty
      expect(texts('    a + "x"', "arithmetic")).to be_empty
    end

    it "changes numeric literals to n+1, n-1 and 0" do
      expect(texts("    a + 5", "literal_number")).to eq(["a + 6", "a + 4", "a + 0"])
      expect(texts("    a + 1.5", "literal_number")).to eq(["a + 2.5", "a + 0.5", "a + 0.0"])
      expect(texts("    a + 0", "literal_number")).to eq(["a + 1", "a + (-1)"])
      expect(texts("    a + 1", "literal_number")).to eq(["a + 2", "a + 0"])
      expect(texts("    a + 0x0", "literal_number")).to eq(["a + 1", "a + (-1)"])
    end
  end

  describe "statements" do
    it "removes each statement of a multi-statement body" do
      expect(texts("    a = 1\n    b = 2\n    a + b", "statement_removal").size).to eq(3)
    end

    it "does not remove the only statement of the body (coarse covers it)" do
      expect(texts("    a + b", "statement_removal")).to be_empty
    end

    it "does not treat expression slots as statements" do
      expect(texts("    x = a ? b : 1\n    y = \"\#{a ? 1 : 2}\"\n    return 1 if a", "statement_removal"))
        .to eq(["nil\n    y = \"\#{a ? 1 : 2}\"\n    return 1 if a",
                "x = a ? b : 1\n    nil\n    return 1 if a"])
    end

    it "does not remove an if/unless without else (the condition mutants are the same change)" do
      body = "    return 1 if a\n    b unless a\n    if a\n      b\n    else\n      c\n    end\n    d"
      removed = texts(body, "statement_removal")
      expect(removed.size).to eq(2) # the if/else and `d`
      expect(removed).to all(include("return 1 if a", "b unless a"))
    end

    it "removes statements inside multi-statement nested bodies" do
      # b, c and d; the else-less if itself is covered by condition_false.
      expect(texts("    if a\n      b\n      c\n    end\n    d", "statement_removal").size).to eq(3)
    end

    it "composes pair removal into the builtin set" do
      expect(texts("    call(a, msg: b, c: d)", "pair_removal")).to eq(["call(a,  c: d)", "call(a, msg: b )"])
    end

    it "treats a logger held in an instance variable, on self or on the root namespace as arid" do
      ["@logger.info(a)", "self.logger.info(a)", "::Rails.logger.info(a)", "Rails.logger.warn(a)"].each do |call|
        expect(texts("    #{call}", "body_nil")).to be_empty, call
      end
    end

    it "treats a logger at the end of a receiver chain as arid (#665)" do
      ["Sentry.sdk_logger.warn(a)", "app.sdk_logger.error(a)",
       "other.logger.info(a)", "foo.bar.logger.debug(a)"].each do |call|
        expect(texts("    #{call}", "body_nil")).to be_empty, call
      end
    end

    it "does not treat a name that merely contains logger, or a non-level call on one, as arid" do
      expect(texts("    @loggers.each(&:flush)", "body_nil")).to eq(["nil"])
      expect(texts("    catalogger.warnings(a)", "body_nil")).to eq(["nil"])
    end

    # The instrument rule still holds for the chain: the CALL is noise but
    # its block is real work, so the lazy log message inside still mutates
    # and its survivors get the arid LABEL from the enclosing call (#665).
    it "still mutates the block body of a chained logger call" do
      expect(texts("    Sentry.sdk_logger.warn(a) do\n      b || c\n    end", "boolean_logic"))
        .to eq(["Sentry.sdk_logger.warn(a) do\n      b\n    end",
                "Sentry.sdk_logger.warn(a) do\n      c\n    end",
                "Sentry.sdk_logger.warn(a) do\n      true\n    end"])
    end

    it "wires the builtin arid list into pair removal" do
      expect(texts("    logger.info(msg: a)\n    a", "pair_removal")).to be_empty
    end

    it "walks the block body of an arid statement: the call is noise, the block is real work" do
      body = "    ActiveSupport::Notifications.instrument \"m.compile\" do |payload|\n      " \
             "payload[:a] = b\n      " \
             "payload[:c] = d || e\n    " \
             "end"
      head = "ActiveSupport::Notifications.instrument \"m.compile\" do |payload|\n"
      expect(texts(body, "statement_removal")).to eq(["#{head}      nil\n      payload[:c] = d || e\n    end",
                                                      "#{head}      payload[:a] = b\n      nil\n    end"])
      expect(texts(body, "boolean_logic").size).to eq(3)
    end

    it "keeps an arid statement with a real block out of nothing-to-remove" do
      body = "    ActiveSupport::Notifications.instrument \"m.compile\" do |payload|\n      " \
             "payload[:a] = b\n    " \
             "end"
      expect(texts(body, "body_nil")).to eq(["nil"])
    end

    it "still treats an arid statement whose block is only noise as noise" do
      expect(texts("    Notifications.instrument(\"x\") { puts y }", "body_nil")).to be_empty
    end

    it "mutates the body when the arid statement's block mixes noise with real work" do
      body = "    Notifications.instrument \"x\" do\n      puts y\n      real_work\n    end"
      expect(texts(body, "body_nil")).to eq(["nil"])
    end

    it "treats an arid call with a &: block argument as noise, not a crash" do
      expect(texts("    p(&:first)", "body_nil")).to be_empty
    end

    it "treats an arid call whose do-block rescues as real work, not a crash (#464)" do
      body = "    Notifications.instrument \"x\" do\n      real_work\n    rescue\n      handle\n    end"
      expect(texts(body, "body_nil")).to eq(["nil"])
    end

    it "treats an arid call whose do-block ensures as real work, not a crash (#464)" do
      body = "    Notifications.instrument \"x\" do\n      real_work\n    ensure\n      cleanup\n    end"
      expect(texts(body, "body_nil")).to eq(["nil"])
    end

    it "still treats an arid statement without a block, or with an empty one, as noise" do
      expect(texts("    Notifications.instrument \"x\"\n    logger.info(a)", "body_nil")).to be_empty
      expect(texts("    Notifications.instrument(\"x\") {}", "body_nil")).to be_empty
    end

    it "wires custom arid patterns into element removal" do
      source = described_class.new(arid: ['\\Atrack\\b'])
      subject = subjects_in("class K\n  def m\n    track([1, 2])\n    use([3, 4])\n  end\nend\n").first
      texts = mutated_texts(subject, source:).filter_map { |op, text| text if op == "element_removal" }
      expect(texts).to all(include("track([1, 2])"))
      expect(texts.map { |t| t[/use\(\[.*?\]\)/] }).to contain_exactly("use([ 4])", "use([3 ])")
    end

    it "registers every single-purpose source in the delegated walk" do
      expect(described_class.new.send(:delegated).size).to eq(23)
    end

    it "wires custom arid patterns into copy replacement" do
      source = described_class.new(arid: ['\Atrack\b'])
      subject = subjects_in("class K\n  def m(x)\n    track(x.dup)\n    use(x.dup)\n  end\nend\n").first
      texts = mutated_texts(subject, source:).filter_map { |op, text| text if op == "copy_replacement" }
      expect(texts.size).to eq(1)
      expect(texts.first).to include("track(x.dup)", "use(x)")
    end

    it "wires custom arid patterns into pair removal" do
      source = described_class.new(arid: ['\Atrack\b'])
      subject = subjects_in("class K\n  def m(a)\n    track(event: a)\n    a\n  end\nend\n").first
      ops = mutated_texts(subject, source:).map(&:first)
      expect(ops).not_to include("pair_removal")
    end

    it "wires custom arid patterns into jump value" do
      source = described_class.new(arid: ['\Areturn a\b'])
      subject = subjects_in("class K\n  def m(a)\n    return a if a\n    a\n  end\nend\n").first
      expect(mutated_texts(subject, source:).map(&:first)).not_to include("jump_value")
      expect(texts("    return a if b", "jump_value")).to eq(["return nil if b"])
    end

    it "composes chain removal into the builtin set" do
      expect(texts("    a.b.c", "chain_removal")).to eq(["a.c"])
    end

    it "wires the builtin arid list into chain removal" do
      expect(texts("    logger.info.debug(a)\n    a", "chain_removal")).to be_empty
    end

    it "wires custom arid patterns into chain removal" do
      source = described_class.new(arid: ['\Atrack\b'])
      subject = subjects_in("class K\n  def m(a)\n    track.event.name\n    a\n  end\nend\n").first
      ops = mutated_texts(subject, source:).map(&:first)
      expect(ops).not_to include("chain_removal")
    end

    it "wires custom arid patterns into endpoint replacement" do
      subject = subjects_in("class K\n  def m(a)\n    track(a.first)\n    a\n  end\nend\n").first
      expect(mutated_texts(subject).map(&:first)).to include("endpoint_replacement")
      source = described_class.new(arid: ['\Atrack\b'])
      expect(mutated_texts(subject, source:).map(&:first)).not_to include("endpoint_replacement")
    end

    it "never mutates arid statements" do
      found = mutations("    logger.info(a + 1)\n    a > b").reject { |op, _| op.start_with?("body_") }
      expect(found.map(&:last)).to all(include("logger.info(a + 1)"))
    end

    it "accepts custom arid patterns" do
      source = described_class.new(arid: ['\Atrack\b'])
      subject = subjects_in("class K\n  def m(a)\n    track(a + 1)\n    a\n  end\nend\n").first
      fine = mutated_texts(subject, source:).reject { |op, _| op.start_with?("body_") }
      expect(fine.map(&:last)).to all(include("track(a + 1)"))
    end
  end

  describe "nil handling" do
    it "turns &. into ." do
      expect(texts("    a&.b", "safe_navigation")).to eq(["a.b"])
    end

    it "turns ||= into =" do
      expect(texts("    @x ||= a", "or_assign")).to eq(["@x = a"])
      expect(texts("    h[a] ||= b", "or_assign")).to eq(["h[a] = b"])
    end

    it "leaves constant targets alone inside a def: X = a is a syntax error there" do
      expect(texts("    X ||= a", "or_assign")).to eq([])
      expect(texts("    A::B ||= a", "or_assign")).to eq([])
    end

    it "mutates constant targets in a define_method body, where X = a is legal" do
      source = "class K\n  define_method(:m) do |a|\n    X ||= a\n    A::B ||= a\n  end\nend\n"
      mutated = mutated_texts(subjects_in(source).first).filter_map { |operator, text| text if operator == "or_assign" }
      expect(mutated.size).to eq(2)
      expect(mutated[0]).to include("X = a").and include("A::B ||= a")
      expect(mutated[1]).to include("X ||= a").and include("A::B = a")
      expect(mutated.map { |text| Prism.parse(text).errors }).to all(be_empty)
    end
  end

  describe "guarded assignment" do
    it "turns &&= into = for every kind of target" do
      expect(texts("    x &&= a", "and_assign")).to eq(["x = a"])
      expect(texts("    @x &&= a", "and_assign")).to eq(["@x = a"])
      expect(texts("    @@x &&= a", "and_assign")).to eq(["@@x = a"])
      expect(texts("    $x &&= a", "and_assign")).to eq(["$x = a"])
      expect(texts("    h[a] &&= b", "and_assign")).to eq(["h[a] = b"])
      expect(texts("    a.b &&= c", "and_assign")).to eq(["a.b = c"])
    end

    it "leaves constant targets alone inside a def: X = a is a syntax error there" do
      expect(texts("    X &&= a", "and_assign")).to eq([])
      expect(texts("    A::B &&= a", "and_assign")).to eq([])
      expect(Prism.parse("def m\n  X = a\nend").errors).not_to be_empty
    end

    it "mutates constant targets in a define_method body, where X = a is legal" do
      source = "class K\n  define_method(:m) do |a|\n    X &&= a\n    A::B &&= a\n  end\nend\n"
      subject = subjects_in(source).first
      mutated = mutated_texts(subject).filter_map { |operator, text| text if operator == "and_assign" }
      expect(mutated.size).to eq(2)
      expect(mutated[0]).to include("X = a").and include("A::B &&= a")
      expect(mutated[1]).to include("X &&= a").and include("A::B = a")
      expect(Prism.parse(mutated[0]).errors).to be_empty
      expect(Prism.parse(mutated[1]).errors).to be_empty
    end

    it "does not touch ||= or +=, which have their own operators" do
      expect(texts("    @x ||= a", "and_assign")).to eq([])
      expect(texts("    @x += a", "and_assign")).to eq([])
    end
  end

  it "never produces a mutation identical to the original, for many shapes" do
    bodies = ["    return if true\n    x = 0\n    y = 0.0\n    z = nil\n    a&.b\n    c.d", "    raise", "    nil",
              "    while true\n      a\n    end\n    b"]
    bodies.each do |body|
      subject = subjects_in("class K\n  def m?(a)\n#{body}\n  end\nend\n").first
      texts = mutated_texts(subject).map(&:last)
      expect(texts).not_to include(subject.source), body
    end
  end

  it "accepts arid patterns given as Regexp objects" do
    source = described_class.new(arid: [/\Atrack\b/])
    subject = subjects_in("class K\n  def m(a)\n    track(a + 1)\n    a\n  end\nend\n").first
    fine = mutated_texts(subject, source:).reject { |op, _| op.start_with?("body_") }
    expect(fine.map(&:last)).to all(include("track(a + 1)"))
  end

  it "handles a body that is only a rescue clause" do
    subject = subjects_in("class K\n  def m\n  rescue StandardError\n    1\n  end\nend\n").first
    expect { described_class.new.mutations_for(subject) }.not_to raise_error
  end

  it "produces text that parses for every mutation of a varied method" do
    body = <<~RUBY.gsub(/^/, "    ")
      return nil unless a&.valid?
      total = 0
      a.items.each { |i| total += i.price * 2 if i.price >= 10 && !i.free? }
      @cache ||= {}
      total > 100 ? total - 5 : total
    RUBY
    expect(mutations(body).map(&:last)).to all(satisfy { |text| Prism.parse("def m\n#{text}\nend").success? })
  end

  it "does not mutate inside nested scopes" do
    expect(mutations("    class << a\n      def x = 1 + 1\n    end\n    a").map(&:first)).not_to include("arithmetic")
  end

  describe "declared return types" do
    def operators(sig, body)
      source = "class K\n  #{sig}\n  def m(a)\n#{body}\n  end\nend\n"
      mutated_texts(subjects_in(source).first).map(&:first)
    end

    it "keeps nil without proof that the runtime rejects it" do
      found = operators("sig { params(a: Integer).returns(Integer) }", "    a + 1")
      expect(found).to include("body_nil")
      expect(found).to include("body_raise", "arithmetic")
    end

    it "keeps nil mutants for checked levels, custom handlers and type expression near misses" do
      ["returns(Integer).checked(:never)", "returns(Integer).checked(:tests)",
       "returns(Integer).checked(:always)", "returns(Integer).on_failure(:log)",
       "returns(T::Boolean)", "returns(T::Array[Integer])", "returns(T::Array[Integer].nilable)",
       "returns(T::BooleanAlias)", "returns(T::Boolean | NilClass)", "returns(Money)",
       "returns(::Integer)", "returns(T.any(Integer, NilClass))"].each do |expression|
        sig = "sig { #{expression} }"
        expect(operators(sig, "    a + 1")).to include("body_nil"), expression
        expect(removals(sig, "    store(a)\n    a + 1").size).to eq(2), expression
      end
    end

    it "does not resolve enclosing or aliased constants to prune mutants" do
      stub_const("Outer", Module.new)
      stub_const("Outer::String", NilClass)
      stub_const("Outer::Money", Class.new)
      source = <<~RUBY
        module Outer
          class Inner
            sig { returns(String) }
            def fee(a)
              store(a)
              a + 1
            end
            sig { returns(Money) }
            def other(a)
              store(a)
              a + 1
            end
          end
        end
      RUBY
      subjects_in(source).each do |subject|
        found = mutated_texts(subject).map(&:first)
        expect(found).to include("body_nil")
        expect(found.count("statement_removal")).to eq(2)
      end
    end

    it "keeps the true and false bodies of a predicate whose sig is T::Boolean" do
      source = "class K\n  sig { returns(T::Boolean) }\n  def ok?(a)\n    a > 1\n  end\nend\n"
      expect(mutated_texts(subjects_in(source).first).map(&:first)).to include("body_true", "body_false")
    end

    it "keeps body_nil when the sig allows nil, is void, or is missing" do
      expect(operators("sig { returns(T.nilable(Integer)) }", "    a + 1")).to include("body_nil")
      expect(operators("sig { void }", "    a + 1")).to include("body_nil")
      expect(operators("", "    a + 1")).to include("body_nil")
    end

    def removals(sig, body)
      source = "class K\n  #{sig}\n  def m(a)\n#{body}\n  end\nend\n"
      mutated_texts(subjects_in(source).first).filter_map { |operator, text| text if operator == "statement_removal" }
    end

    it "keeps last-statement removal without proof of runtime enforcement" do
      removed = removals("sig { returns(Integer) }", "    log(a)\n    store(a)\n    a + 1")
      expect(removed.size).to eq(3)
      expect(removed.last).not_to include("a + 1")
    end

    it "still removes the last statement when the sig allows nil" do
      expect(removals("sig { returns(T.nilable(Integer)) }", "    store(a)\n    log(a)").size).to eq(2)
    end
  end

  it "forgets the subject it walked once it is done, also when the walk raises" do
    source = described_class.new
    subject = subjects_in("class K\n  def m(x)\n    x + 1\n  end\nend\n").first
    source.mutations_for(subject)
    expect(source.instance_variable_get(:@subject)).to be_nil
    allow(source).to receive(:visit).and_raise("boom")
    expect { source.mutations_for(subject) }.to raise_error("boom")
    expect(source.instance_variable_get(:@subject)).to be_nil
  end
end
