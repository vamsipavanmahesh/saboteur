# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::MutationSource::HazardGuard do
  def partition(source, patterns: nil)
    subject = subjects_in("class K\n  def m\n#{source}\n  end\nend\n").first
    mutations = Saboteur::MutationSource::Builtin.new.mutations_for(subject)
    guard = described_class.new(patterns || described_class::DEFAULT_HAZARD)
    kept, suppressed = guard.partition(mutations.map { |mutation| [mutation, nil] }, subject)
    [kept.map(&:first).map(&:operator), suppressed.map(&:first).map(&:operator), subject, mutations]
  end

  it "suppresses mutants inside the arguments of FileUtils.rm_rf (issue #102)" do
    _kept, suppressed, = partition('    FileUtils.rm_rf(File.join(Dir.pwd, "build"))')
    expect(suppressed).to include("literal_string")
  end

  it "keeps the coarse mutants that destroy the call instead of running it" do
    kept, = partition('    FileUtils.rm_rf(File.join(Dir.pwd, "build"))')
    expect(kept).to include("body_nil", "body_raise")
  end

  it "suppresses bare Kernel process spawns" do
    _kept, suppressed, = partition('    system("make clean")')
    expect(suppressed).not_to be_empty
  end

  it "suppresses the explicit-receiver spellings of process spawns" do
    %w[Kernel Process].each do |receiver|
      _kept, suppressed, = partition(%(    #{receiver}.spawn("make clean")))
      expect(suppressed).not_to be_empty, "expected #{receiver}.spawn to be suppressed"
    end
    _kept, suppressed, = partition('    Kernel.system("make clean")')
    expect(suppressed).not_to be_empty
  end

  it "suppresses bare FileUtils calls, as written after include FileUtils" do
    _kept, suppressed, = partition('    rm_rf(File.join(Dir.pwd, "build"))')
    expect(suppressed).not_to be_empty
  end

  # FileUtils.send(:rm_rf, x) is FileUtils.rm_rf with indirection (#240);
  # a dynamic selector stays documented as out of scope.
  # A literal argument to any other method is not a send selector:
  # logger.info("rmtree") runs nothing destructive, so its mutants run.
  it "does not resolve literal arguments of non-send methods as selectors" do
    kept, suppressed, = partition('    logger.info("rmtree")')
    expect(suppressed).to be_empty
    expect(kept).to include("body_raise")
  end

  # Only send-family calls resolve their first argument as the selector:
  # dropping the SEND_NAMES conjunct would treat any method's literal
  # first argument as the call being made.
  it "resolves the hazard selector only for send, public_send and __send__" do
    kept, suppressed, = partition('    process(:system, "make clean")')
    expect(suppressed).to be_empty
    expect(kept).to include("body_raise")
  end

  it "suppresses mutants when send, public_send or __send__ names a hazard with a literal selector" do
    ['    FileUtils.send(:rm_rf, File.join(Dir.pwd, "build"))',
     '    FileUtils.public_send("rm_rf", File.join(Dir.pwd, "build"))',
     '    __send__(:rm_rf, File.join(Dir.pwd, "build"))'].each do |call|
      _kept, suppressed, = partition(call)
      expect(suppressed).not_to be_empty, "expected mutants to be suppressed for #{call}"
    end
  end

  # #294 review: the resolved selector must face the same direct-call
  # semantics, with the arguments shifted past the selector - otherwise
  # helper.send(:rmtree, x), a Pathname receiver and piped open slip through.
  it "suppresses a send-indirected rmtree on any receiver, like the direct call" do
    ['    helper.send(:rmtree, "build")',
     '    path.public_send(:rmtree, "build")',
     '    helpers.__send__("rmtree", "build")'].each do |call|
      _kept, suppressed, = partition(call)
      expect(suppressed).not_to be_empty, "expected mutants to be suppressed for #{call}"
    end
  end

  it "suppresses a piped open reached through send, bare or on Kernel" do
    ['    Kernel.send(:open, "| cmd")',
     '    __send__(:open, "| cmd")',
     '    send(:open, "| \#{cmd}")'].each do |call|
      _kept, suppressed, = partition(call)
      expect(suppressed).not_to be_empty, "expected mutants to be suppressed for #{call}"
    end
  end

  it "keeps a literal send selector that names no hazard, even on a Kernel receiver" do
    _kept, suppressed, = partition('    Kernel.send(:puts, "hi")')
    expect(suppressed).to be_empty
  end

  it "keeps mutants when send names a benign method or the selector is dynamic" do
    _kept, suppressed, = partition("    helper.send(:size)")
    expect(suppressed).to be_empty
    _kept, suppressed, = partition("    FileUtils.send(method, target)")
    expect(suppressed).to be_empty
  end

  # system("rm -rf #{dir}") with the interpolation removed still runs a
  # destructive call with altered inputs (#239 interaction).
  it "suppresses interpolation_removal mutants inside a destructive call" do
    _kept, suppressed, = partition('    system("rm -rf #{dir}")') # rubocop:disable Lint/InterpolationCheck
    expect(suppressed).to include("interpolation_removal")
  end

  it "keeps mutants on benign explicit-receiver calls that share a hazard name" do
    kept, suppressed, = partition('    helper.system("make clean")')
    expect(suppressed).to be_empty
    expect(kept).to include("literal_string")
  end

  it "keeps mutants on Kernel calls outside the hazard list" do
    kept, suppressed, = partition('    Kernel.puts("make clean")')
    expect(suppressed).to be_empty
    expect(kept).to include("literal_string")
  end

  it "does not treat an interpolated open with a dynamic first part as a pipe spawn" do
    _kept, suppressed, = partition("    open(\"\#{name}|ls\")")
    expect(suppressed).to be_empty
  end

  it "keeps every mutant on a clean subject, even one whose replacement does not parse alone" do
    subject = subjects_in("class K\n  def m\n    1 + 2\n  end\nend\n").first
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: subject.file_source.index("1"),
                                              end_byte: subject.file_source.index("1") + 1, replacement: " | ")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test", edits: [edit])
    kept, suppressed = described_class.new.partition([[mutation, nil]], subject)
    expect(suppressed).to be_empty
    expect(kept).to eq([[mutation, nil]])
  end

  it "treats backticks/%x literals as hazardous spans" do
    source = "class K\n  def m\n    `ls -la`\n  end\nend\n"
    subject = subjects_in(source).first
    xstring_start = subject.file_source.index("`")
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: xstring_start + 1,
                                              end_byte: xstring_start + 3, replacement: "pwd")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                      edits: [edit])
    _kept, suppressed = described_class.new.partition([[mutation, nil]], subject)
    expect(suppressed.size).to eq(1)
  end

  it "suppresses a negation removal whose replacement keeps the call alive" do
    _kept, suppressed, = partition('    keep if !system("make")')
    expect(suppressed).to include("negation_removal")
  end

  it "suppresses a whole-call replacement that reintroduces the same call" do
    source = "class K\n  def m\n    FileUtils.rm_rf(\"build\")\n  end\nend\n"
    subject = subjects_in(source).first
    span_start = subject.file_source.index("FileUtils.rm_rf")
    span_end = span_start + "FileUtils.rm_rf(\"build\")".size
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: span_start,
                                              end_byte: span_end, replacement: "FileUtils.rm_rf(\".\")")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                      edits: [edit])
    kept, suppressed = described_class.new.partition([[mutation, nil]], subject)
    expect([kept.size, suppressed.size]).to eq([0, 1])
  end

  it "suppresses a whole-call replacement that retains a nested hazard" do
    source = "class K\n  def m\n    FileUtils.rm_rf(`ls -la`)\n  end\nend\n"
    subject = subjects_in(source).first
    span_start = subject.file_source.index("FileUtils.rm_rf")
    span_end = span_start + "FileUtils.rm_rf(`ls -la`)".size
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: span_start,
                                              end_byte: span_end, replacement: "backup(`ls -la`)")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                      edits: [edit])
    kept, suppressed = described_class.new.partition([[mutation, nil]], subject)
    expect([kept.size, suppressed.size]).to eq([0, 1])
  end

  it "suppresses a whole-call replacement that does not parse on its own" do
    source = "class K\n  def m\n    FileUtils.rm_rf(\"build\")\n  end\nend\n"
    subject = subjects_in(source).first
    span_start = subject.file_source.index("FileUtils.rm_rf")
    span_end = span_start + "FileUtils.rm_rf(\"build\")".size
    edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: span_start,
                                              end_byte: span_end, replacement: "x +")
    mutation = Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test",
                                                      edits: [edit])
    kept, suppressed = described_class.new.partition([[mutation, nil]], subject)
    expect([kept.size, suppressed.size]).to eq([0, 1])
  end

  it "suppresses Open3, IO.popen and rmtree on any receiver" do
    _kept, suppressed, = partition('    Open3.capture3("git", "status")')
    expect(suppressed).not_to be_empty
    _kept, suppressed2, = partition('    IO.popen("ls") { |io| io.read }')
    expect(suppressed2).not_to be_empty
  end

  it "suppresses any Open3 method, not only the common ones" do
    _kept, suppressed, = partition('    Open3.pipeline("cat a", "grep b")')
    expect(suppressed).not_to be_empty
  end

  it "still catches rmtree by name with a custom pattern list" do
    _kept, suppressed, = partition('    rmtree("build")', patterns: ["Deploys.destroy_everything"])
    expect(suppressed).not_to be_empty
  end

  it "judges piped open by its first argument only" do
    _kept, suppressed, = partition('    open("| ls", "r")')
    expect(suppressed).not_to be_empty
    kept2, suppressed2, = partition('    open("file.txt", "| ls")')
    expect(suppressed2).to be_empty
    expect(kept2).not_to be_empty
  end

  it "suppresses Kernel#open with a leading pipe but leaves a plain open alone" do
    _kept, suppressed, = partition('    open("| ls")')
    expect(suppressed).not_to be_empty
    kept, suppressed2, = partition('    open("file.txt")')
    expect(suppressed2).to be_empty
    expect(kept).to include("literal_string")
  end

  it "does not treat a pipe string handed to other methods as a spawn" do
    _kept, suppressed, = partition('    foo("| ls")')
    expect(suppressed).to be_empty
  end

  it "suppresses an explicit Kernel.open with a leading pipe" do
    _kept, suppressed, = partition('    Kernel.open("| ls")')
    expect(suppressed).not_to be_empty
  end

  it "leaves open on other receivers alone even with a pipe string" do
    _kept, suppressed, = partition('    Foo.open("| ls")')
    expect(suppressed).to be_empty
  end

  it "handles a bare open with no arguments" do
    _kept, suppressed, = partition("    open()")
    expect(suppressed).to be_empty
  end

  it "suppresses Kernel#open with an interpolated argument that starts with a pipe" do
    _kept, suppressed, = partition('    open("| #{dir} -la")') # rubocop:disable Lint/InterpolationCheck
    expect(suppressed).not_to be_empty
  end

  it "leaves an interpolated open argument that starts with plain text alone" do
    _kept, suppressed, = partition('    open("file #{dir}.txt")') # rubocop:disable Lint/InterpolationCheck
    expect(suppressed).to be_empty
  end

  it "leaves an open whose argument is a plain variable alone" do
    _kept, suppressed, = partition("    open(path)")
    expect(suppressed).to be_empty
  end

  it "leaves ordinary calls fully mutable" do
    _kept, suppressed, = partition('    File.read("build/out.txt")')
    expect(suppressed).to be_empty
  end

  it "honours custom hazard patterns" do
    guard_tags = ["Deploys.destroy_everything"]
    _kept, suppressed, = partition('    Deploys.destroy_everything("prod")', patterns: guard_tags)
    expect(suppressed).to include("literal_string")
  end

  it "suppresses every edit in a method while any hazardous call survives it" do
    source = "class K\n  def m\n    FileUtils.rm_rf(File.join(Dir.pwd, \"build\"))\n  end\nend\n"
    subject = subjects_in(source).first
    guard = described_class.new
    span_start = subject.file_source.index("FileUtils.rm_rf")
    span_end = span_start + "FileUtils.rm_rf(File.join(Dir.pwd, \"build\"))".size

    def mutation_at(subject, start_byte, end_byte, replacement: "x")
      edit = Saboteur::MutationSource::Edit.new(file: subject.file, start_byte: start_byte,
                                                end_byte: end_byte, replacement: replacement)
      Saboteur::MutationSource::Mutation.new(subject_id: subject.id, operator: "test", edits: [edit])
    end

    suppressed_cases = {
      "strictly left of the call" => [span_start - 5, span_start - 2],
      "abutting the call on the left" => [span_start - 3, span_start],
      "abutting the call on the right" => [span_end, span_end + 3],
      "strictly right of the call" => [span_end + 2, span_end + 5],
      "inside the call" => [span_start + 3, span_end - 3],
      "from inside the call past its end" => [span_start + 3, span_end + 2],
      "from before the call into its interior" => [span_start - 2, span_end - 2]
    }
    suppressed_cases.each do |label, (start_byte, end_byte)|
      kept, suppressed = guard.partition([[mutation_at(subject, start_byte, end_byte), nil]], subject)
      expect([kept.size, suppressed.size]).to eq([0, 1]), "expected edit #{label} to be suppressed"
    end

    kept_cases = {
      "covering the call with overflow on the left" => [span_start - 2, span_end],
      "covering the call with overflow on the right" => [span_start, span_end + 2],
      "covering the call exactly" => [span_start, span_end]
    }
    kept_cases.each do |label, (start_byte, end_byte)|
      kept, suppressed = guard.partition([[mutation_at(subject, start_byte, end_byte), nil]], subject)
      expect([kept.size, suppressed.size]).to eq([1, 0]), "expected edit #{label} to be kept"
    end

    same_call = mutation_at(subject, span_start, span_end,
                            replacement: "FileUtils.rm_rf(File.join(Dir.pwd, \"build\"))")
    kept, suppressed = guard.partition([[same_call, nil]], subject)
    expect([kept.size, suppressed.size]).to eq([0, 1])
  end
end

RSpec.describe Saboteur::MutationSource::HazardGuard, "#load_time_hazards (#319)" do
  def slices(text)
    described_class.new.load_time_hazards(Prism.parse(text).value)
  end

  it "flags side-effecting top-level and class-body code" do
    expect(slices("FileUtils.rm_rf(\"/tmp/x\")\nclass A\n  system(\"ls\")\nend\n"))
      .to contain_exactly("FileUtils.rm_rf(\"/tmp/x\") (line 1)", "system(\"ls\") (line 3)")
  end

  it "ignores def bodies: they run when called, not at load" do
    expect(slices("def clean\n  FileUtils.rm_rf(\"/tmp/x\")\nend\n")).to be_empty
  end

  it "flags a hazardous call inside a block that runs at load" do
    expect(slices("3.times { system(\"ls\") }\n")).to eq(["system(\"ls\") (line 1)"])
  end

  it "leaves a pure literal assignment alone" do
    expect(slices("RULES = { a: 1 }.freeze\n")).to be_empty
  end

  # The walk stops at a hazardous call: inner calls run inside the outer
  # one, so reporting them too would only repeat the span. Dropping the
  # `next` would also descend into the backtick spawn inside rm_rf.
  it "does not descend into a hazardous call to find nested hazards" do
    expect(slices("FileUtils.rm_rf(`ls /tmp`)\n")).to eq(["FileUtils.rm_rf(`ls /tmp`) (line 1)"])
  end
end

RSpec.describe Saboteur::MutationSource::HazardGuard, "#unvetted_load_code (#319)" do
  def slices(text)
    described_class.new.unvetted_load_code(Prism.parse(text).value)
  end

  it "flags a require whose argument or block runs code on every replay" do
    flagged = slices(<<~RUBY)
      require(build_path)
      require_relative(begin
        "helper"
      end)
      require("x") { register! }
      RULES = { a: 1 }
    RUBY
    expect(flagged).to eq(["require(build_path) (line 1)", "require_relative(begin (line 2)",
                           'require("x") { register! } (line 5)'])
    expect(slices("require \"json\"\nrequire_relative \"helper\"\nRULES = { a: 1 }\n")).to eq([])
  end

  # A vetted require is exactly one literal string argument to a
  # SAFE_LOAD_REQUIRES name and nothing else: each conjunct stops a
  # different abuse, so each gets its own flagged case here.
  it "flags requires with extra or missing arguments and other single-string calls" do
    expect(slices("require(\"a\", \"b\")\n")).to eq(['require("a", "b") (line 1)'])
    expect(slices("require(build_path, \"a\")\n")).to eq(["require(build_path, \"a\") (line 1)"])
    expect(slices("require()\n")).to eq(["require() (line 1)"])
    expect(slices("system(\"ls\")\n")).to eq(['system("ls") (line 1)'])
  end

  it "passes requires, pure defs, nesting with a constant superclass and literal assignments" do
    expect(slices(<<~RUBY)).to eq([])
      require "json"
      require_relative "x"
      module M
        class A < Base::Sub
          RULES = { a: 1, b: [true, nil, "s", :sym, 1.5, X::Y] }.freeze
          EMPTY = {}
          LIST = [1, "a"]
          def call(x) = x
        end
        class B
        end
      end
    RUBY
  end

  it "flags a def-free statement even inside a vetted nesting" do
    expect(slices("class A\n  RULES = [1]\n  boot!\nend\n")).to eq(["boot! (line 3)"])
    expect(slices("class A < Struct.new(:x)\nend\n")).to eq(["Struct.new(:x) (line 1)"])
  end

  # A bare constant superclass reads a constant just like a qualified
  # Base::Sub path does; treating it as unvetted would flag plain
  # inheritance as load-time code.
  it "passes a class with a bare constant superclass" do
    expect(slices("class A < Base\nend\n")).to eq([])
  end

  it "flags calls that are not bare requires" do
    expect(slices("foo.require(\"x\")\n")).to eq(["foo.require(\"x\") (line 1)"])
    expect(slices("validate!(RULES)\n")).to eq(["validate!(RULES) (line 1)"])
    expect(slices("1.times { boot! }\n")).to eq(["1.times { boot! } (line 1)"])
    expect(slices("if flag\n  RULES = [1]\nend\n")).to eq(["if flag (line 1)"])
  end

  it "flags assignments whose values are not plain literals" do
    expect(slices("RULES = build_rules\n")).to eq(["RULES = build_rules (line 1)"])
    expect(slices("RULES = { a: build }\n")).to eq(["RULES = { a: build } (line 1)"])
    expect(slices("RULES = { build => 1 }\n")).to eq(["RULES = { build => 1 } (line 1)"])
    expect(slices("RULES = { **other }\n")).to eq(["RULES = { **other } (line 1)"])
    expect(slices("RULES = [1, build]\n")).to eq(["RULES = [1, build] (line 1)"])
    expect(slices("RULES = [1].freeze(true)\n")).to eq(["RULES = [1].freeze(true) (line 1)"])
    expect(slices("RULES = [1].freeze { 2 }\n")).to eq(["RULES = [1].freeze { 2 } (line 1)"])
    expect(slices("RULES = [1].dup\n")).to eq(["RULES = [1].dup (line 1)"])
    # .freeze only vets a value when the frozen receiver is itself plain
    # data; freezing a computed call still runs the call at load.
    expect(slices("RULES = build_rules.freeze\n")).to eq(["RULES = build_rules.freeze (line 1)"])
    # An interpolated string is built at load from its parts, so it is
    # not a plain literal even though a plain string is.
    expect(slices(%(RULES = "a\#{1}"\n))).to eq([%(RULES = "a\#{1}" (line 1))])
  end

  it "passes a frozen regex literal but not a computed or interpolated one (#664)" do
    expect(slices("OFFSET = /\\A([+-]\\d{1,2})\\z/.freeze\n")).to eq([])
    expect(slices("OFFSET = /\\A\\d\\z/\n")).to eq([])
    expect(slices(%(OFFSET = /a\#{1}/.freeze\n))).to eq([%(OFFSET = /a\#{1}/.freeze (line 1))])
    expect(slices("OFFSET = Regexp.new(build)\n")).to eq(["OFFSET = Regexp.new(build) (line 1)"])
  end

  it "passes a class << self holding defs and bare visibility calls (#664)" do
    expect(slices(<<~RUBY)).to eq([])
      module M
        LIST = [1, 2].freeze
        OFFSET = /\\A\\d+\\z/.freeze
        class << self
          def from_cron(cron) = cron
          private
          def options = {}
          protected :options
        end
      end
    RUBY
  end

  it "still flags side-effecting code inside class << self (#664)" do
    expect(slices("class << self\n  boot!\nend\n")).to eq(["boot! (line 2)"])
    expect(slices("class << self\n  private build\nend\n")).to eq(["private build (line 2)"])
  end

  it "flags a class << target whose expression runs at load (#664)" do
    expect(slices("class << SomeFactory.build\n  def x = 1\nend\n"))
      .to eq(["class << SomeFactory.build (line 1)"])
    expect(slices("class << REGISTRY\n  def x = 1\nend\n")).to eq([])
    expect(slices("class << @registry\n  def x = 1\nend\n")).to eq([])
  end

  it "pins the visibility-call receiver and block conjuncts (#664)" do
    expect(slices("self.private :x\n")).to eq(["self.private :x (line 1)"])
    expect(slices("private :x do |y| y end\n")).to eq(["private :x do |y| y end (line 1)"])
  end

  it "passes bare visibility calls in a class body (#664)" do
    expect(slices("class A\n  private\n  def x = 1\n  public :x\nend\n")).to eq([])
    expect(slices("class A\n  private def y = 2\nend\n")).to eq([])
  end

  it "cuts a long citation to its first 60 characters plus the line (#664)" do
    long_call = "register!(\"#{'a' * 80}\")"
    flagged = slices("#{long_call}\n")
    expect(flagged).to eq(["#{long_call[0, 57]}... (line 1)"])
    expect(flagged.first.length).to be <= 71
  end

  # The boundary is strict: a first line of 60 characters is kept whole,
  # 61 or more is cut to 57 plus an ellipsis. Indentation is stripped
  # before measuring, and a multiline call cites its first line only.
  it "keeps a 60-character first line whole and cuts 61 or more (#664)" do
    line60 = "register!(:#{'a' * 48})" # 60 characters
    expect(line60.length).to eq(60)
    expect(slices("#{line60}\n")).to eq(["#{line60} (line 1)"])
    line61 = "register!(:#{'a' * 49})"
    expect(line61.length).to eq(61)
    expect(slices("#{line61}\n")).to eq(["#{line61[0, 57]}... (line 1)"])
    line70 = "register!(:#{'a' * 58})"
    expect(line70.length).to eq(70)
    expect(slices("#{line70}\n")).to eq(["#{line70[0, 57]}... (line 1)"])
  end

  it "strips indentation and cites a multiline call by its first line (#664)" do
    expect(slices("class A\n    boot!\nend\n")).to eq(["boot! (line 2)"])
    expect(slices("Registry.register(\n  :x\n)\n")).to eq(["Registry.register( (line 1)"])
  end

  it "passes a Struct/Data class factory with literal arguments and no block (#537)" do
    expect(slices("VerificationContext = Struct.new(:payload, keyword_init: true)\n")).to eq([])
    expect(slices("Point = Data.define(:x)\n")).to eq([])
    expect(slices("Named = Struct.new(\"Kind\", :x, keyword_init: false)\n")).to eq([])
    expect(slices("Point = Struct.new\n")).to eq([])
  end

  it "flags a factory with a block, a computed argument, or another receiver (#537)" do
    expect(slices("Point = Data.define(:x) { def y = 1 }\n"))
      .to eq(["Point = Data.define(:x) { def y = 1 } (line 1)"])
    expect(slices("Ctx = Struct.new(build)\n")).to eq(["Ctx = Struct.new(build) (line 1)"])
    expect(slices("Ctx = Struct.new(:x, keyword_init: build)\n"))
      .to eq(["Ctx = Struct.new(:x, keyword_init: build) (line 1)"])
    expect(slices("Ctx = Class.new\n")).to eq(["Ctx = Class.new (line 1)"])
    # A **OPTS argument is an AssocSplatNode, not an AssocNode: the keyword
    # guard must reject it as not-a-plain-bool, not reach for a #key it
    # does not have (#537).
    expect(slices("X = Struct.new(:a, **OPTS)\n")).to eq(["X = Struct.new(:a, **OPTS) (line 1)"])
    expect(slices("Ctx = Struct.define(:x)\n")).to eq(["Ctx = Struct.define(:x) (line 1)"])
    expect(slices("Ctx = Data.new(:x)\n")).to eq(["Ctx = Data.new(:x) (line 1)"])
  end

  it "flags a factory keyword hash with a non-symbol key or a computed pair among literals (#537)" do
    expect(slices("Ctx = Struct.new(:a, \"kw\" => compute)\n"))
      .to eq(["Ctx = Struct.new(:a, \"kw\" => compute) (line 1)"])
    expect(slices("Ctx = Struct.new(:a, \"kw\" => true)\n"))
      .to eq(["Ctx = Struct.new(:a, \"kw\" => true) (line 1)"])
    expect(slices("Ctx = Struct.new(:a, keyword_init: true, mode: compute)\n"))
      .to eq(["Ctx = Struct.new(:a, keyword_init: true, mode: compute) (line 1)"])
  end

  it "passes private_constant and public_constant with literal names (#537)" do
    expect(slices("module M\n  X = [1]\n  private_constant(:X)\nend\n")).to eq([])
    expect(slices("module M\n  X = [1]\n  private_constant \"X\"\nend\n")).to eq([])
    expect(slices("public_constant :X\n")).to eq([])
  end

  it "passes a hash of lambdas: the bodies run when called, not at load (#537)" do
    expect(slices("VERIFIERS = {\n  verify_iat: ->(options) { Claims::IssuedAt.new(leeway: options[:l]) }\n}.freeze\n"))
      .to eq([])
  end

  it "does not treat a hazardous call inside a load-level lambda as a load-time hazard (#537)" do
    expect(described_class.new.load_time_hazards(Prism.parse("HANDLERS = { a: -> { system(\"ls\") } }\n").value))
      .to eq([])
  end

  it "flags a constant-visibility call with a computed name or a receiver (#537)" do
    expect(slices("private_constant(build)\n")).to eq(["private_constant(build) (line 1)"])
    expect(slices("module M\n  X = [1]\n  private_constant :X, build\nend\n"))
      .to eq(["private_constant :X, build (line 3)"])
    expect(slices("self.private_constant(:X)\n")).to eq(["self.private_constant(:X) (line 1)"])
  end
end
