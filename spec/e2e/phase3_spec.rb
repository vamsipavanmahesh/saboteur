# SPDX-License-Identifier: MIT
# frozen_string_literal: true

require "open3"

RSpec.describe "saboteur run: diff mode, ignore list, exit codes", :e2e do
  let(:dir) { copy_fixture("people") }

  def git(*args)
    _out, err, status = Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
    raise err unless status.success?
  end

  def subject_lines(run)
    mutants(run).map { |m| m["location"]["start"]["line"] }.uniq.sort
  end

  describe "--since" do
    before do
      git("init", "-q")
      git("add", ".")
      git("commit", "-q", "-m", "base")
    end

    it "mutates only methods whose lines changed since the ref" do
      path = File.join(dir, "lib", "people.rb")
      File.write(path, File.read(path).sub("@age}", "@age.to_s}"))
      run = saboteur(dir, "--since", "HEAD", "--all")
      expect(subject_lines(run)).to eq([31])
      expect(run.out).to include("1 subjects")
    end

    it "mutates only the changed lines of a changed method, plus its coarse mutants" do
      path = File.join(dir, "lib", "stage.rb")
      File.write(path, File.read(path).sub("label.upcase", "label.downcase"))
      run = saboteur(dir, "--since", "HEAD", "--all")
      fine = mutants(run).reject { |m| m["mutatorName"].start_with?("body_") }
      expect(fine.map { |m| m["location"]["start"]["line"] }.uniq).to eq([10])
      expect(mutants(run).map { |m| m["mutatorName"] }).to include("body_nil", "body_raise")
    end

    it "mutates the methods of an untracked file, as fully changed (#295)" do
      File.write(File.join(dir, "lib", "fresh.rb"), <<~RUBY)
        class Fresh
          def kind = :fresh
        end
      RUBY
      File.write(File.join(dir, "spec", "fresh_spec.rb"), <<~RUBY)
        require_relative "../lib/fresh"

        RSpec.describe Fresh do
          it("has a kind") { expect(described_class.new.kind).to eq(:fresh) }
        end
      RUBY
      run = saboteur(dir, "--since", "HEAD", "--all")
      expect(run.out).to include("1 subjects")
      expect(run.json.fetch("files").keys).to eq(["lib/fresh.rb"])
      expect(mutants(run).map { |m| m["status"] }).to include("Killed")
    end

    it "warns when an untracked file carries no subject (#295)" do
      File.write(File.join(dir, "lib", "notes.rb"), "KIND = :notes\n")
      run = saboteur(dir, "--since", "HEAD", "--all")
      expect(run.status).to eq(0)
      expect(run.out).to include("0 subjects, 0 mutants")
      expect(run.out).to include("warning: --since: 1 changed Ruby file(s) have no subjects covering the changed lines")
      expect(run.out).to include("notes.rb")
    end

    it "reports an unreadable included file as incomplete beside tested source (#297)" do
      File.write(File.join(dir, "lib", "fresh.rb"), "class Fresh\n  def kind = :fresh\nend\n")
      File.write(File.join(dir, "spec", "fresh_spec.rb"), <<~RUBY)
        require_relative "../lib/fresh"

        RSpec.describe Fresh do
          it("has a kind") { expect(described_class.new.kind).to eq(:fresh) }
        end
      RUBY
      Dir.mktmpdir do |outside|
        File.write(File.join(outside, "target.rb"), "class Omitted\n  def kind = :omitted\nend\n")
        File.symlink(File.join(outside, "target.rb"), File.join(dir, "lib", "omitted.rb"))

        run = saboteur(dir, "--since", "HEAD", "--all", "--agent")
        payload = JSON.parse(run.out)
        expect([run.status, payload["status"], payload["verdict"], payload["exitCode"]])
          .to eq([3, "partial", "incomplete", 3])
        expect(payload["incomplete"]).to include("reason" => "unreadable", "count" => 1,
                                                 "meaning" => "included untracked files could not be read; " \
                                                              "their subjects were not covered")
        expect(payload.dig("counts", "killed")).to be_positive
        expect(payload["warnings"].join).to include("1 included untracked file(s) could not be read")
      end
    end

    it "mutates nothing, says so, and exits 0 when nothing changed (#659)" do
      run = saboteur(dir, "--since", "HEAD", "--all")
      expect(run.status).to eq(0)
      expect(run.out).to include("0 subjects, 0 mutants")
      expect(run.err).to include("--since HEAD: nothing to test - the resolved range has no changes")
    end

    it "mutates nothing, names the count and reason, and exits 0 on a docs-only diff (#659)" do
      File.write(File.join(dir, "README.md"), "# docs only\n")
      git("add", "README.md")
      git("commit", "-q", "-m", "docs")
      run = saboteur(dir, "--since", "HEAD~1", "--all")
      expect(run.status).to eq(0)
      expect(run.out).to include("0 subjects, 0 mutants")
      expect(run.err).to include("--since HEAD~1: nothing to test - 1 changed file, none in mutation scope")
    end

    # A misspelled --subject must not read as a green zero-subject run
    # in CI (#379).
    it "exits 2 when every --subject pattern matches nothing" do
      run = saboteur(dir, "--all", "--subject", "People::Person#typo_xyz")
      expect(run.status).to eq(2)
      expect(run.err).to include("--subject People::Person#typo_xyz matches no subject")
    end

    it "keeps the run and reports the matched count when one --subject pattern misses" do
      run = saboteur(dir, "--all", "--subject", "People::Person#adult?", "--subject", "People::Person#typo_xyz")
      expect(run.status).not_to eq(2)
      expect(run.out).to include('warning: fix the --subject pattern "People::Person#typo_xyz": ' \
                                 "it matches no subject")
      expect(run.out).to include("warning: 1 of 2 --subject patterns matched")
      expect(mutants(run)).not_to be_empty
    end

    it "exits 2 for an unknown ref, before the target boots" do
      run = saboteur(dir, "--since", "no-such-ref", "--all")
      expect(run.status).to eq(2)
      expect(run.err).to include("--since no-such-ref: not a commit in this repository")
      expect(run.err).not_to include("checking the unchanged suite")
    end

    it "skips a method changed only by a comment" do
      path = File.join(dir, "lib", "people.rb")
      File.write(path, File.read(path).sub("@age = age", "# a note\n      @age = age"))
      run = saboteur(dir, "--since", "HEAD", "--all")
      expect(run.status).to eq(0)
      expect(run.err).to include("differ only in comments or formatting")
      expect(run.out).to include("0 subjects, 0 mutants")
    end

    it "runs with --test alone, since the diff already names the sources" do
      path = File.join(dir, "lib", "people.rb")
      File.write(path, File.read(path).sub("@age}", "@age.to_s}"))
      run = saboteur(dir, "--since", "HEAD", "--test", "spec/person_spec.rb", env: { "SABOTEUR_E2E_TRACE" => "1" })
      expect(run.status).to be_between(0, 1)
      expect(run.err).not_to include("--test needs at least one source file")
      expect(run.err).not_to include("running the loaded suite unscoped")
      # The baseline and coverage passes ran the chosen spec, not the suite.
      expect(run.err).to include("building coverage map (runs the selected specs once)")
      # Execution evidence: RSpec loaded only the chosen spec, across the
      # baseline passes, the coverage pass and every mutant run.
      loaded = File.read(File.join(dir, "tmp", "loaded_specs.log")).lines.map(&:chomp)
      expect(loaded).not_to be_empty
      expect(loaded.uniq).to eq(["person_spec.rb"])
    end

    it "scopes to the specs named after the changed files by default" do
      path = File.join(dir, "lib", "stage.rb")
      File.write(path, File.read(path).sub("label.upcase", "label.downcase"))
      run = saboteur(dir, "--since", "HEAD", "--verbose")
      expect(run.status).to be_between(0, 1)
      expect(run.err).to include("inferred specs: running only spec/stage_spec.rb.")
      expect(run.err).to include("building coverage map (runs the selected specs once)")
      expect(run.err).not_to include("running the loaded suite unscoped")
    end

    it "narrows to the matched specs and skips files whose changed lines touch no method" do
      people = File.join(dir, "lib", "people.rb")
      File.write(people, File.read(people).sub("@age = age", "# a note\n      @age = age"))
      stage = File.join(dir, "lib", "stage.rb")
      File.write(stage, File.read(stage).sub("label.upcase", "label.downcase"))
      run = saboteur(dir, "--since", "HEAD", "--verbose")
      expect(run.err).to include("inferred specs: running only spec/stage_spec.rb.")
      expect(run.err).to include("no spec is required for lib/people.rb")
      expect(run.err).not_to include("running the loaded suite unscoped")
    end

    it "records the guessed specs in agent provenance and reports uncovered mutants as no coverage" do
      path = File.join(dir, "lib", "stage.rb")
      File.write(path, File.read(path).sub("label.upcase", "label.downcase"))
      run = saboteur(dir, "--since", "HEAD", "--agent")
      expect(run.err).to include("is reported as NoCoverage")
      payload = JSON.parse(run.out)
      expect(payload.dig("provenance", "selection", "tests", "first")).to eq(["spec/stage_spec.rb"])
      expect(payload.fetch("incomplete").map { |reason| reason["reason"] }).to include("no_coverage")
      expect(JSON.generate(payload.fetch("next", {}))).not_to include("--guess-tests")
    end

    # person_spec.rb reads People::Person, so a spec-less lib/people.rb would
    # be chosen by constant reference; the stop needs a file nothing reads.
    def without_reader
      FileUtils.rm_f(File.join(dir, "spec", "person_spec.rb"))
    end

    it "stops before boot when a changed file has no spec named after it" do
      without_reader
      path = File.join(dir, "lib", "people.rb")
      File.write(path, File.read(path).sub("@age}", "@age.to_s}"))
      run = saboteur(dir, "--since", "HEAD")
      expect(run.status).to eq(2)
      expect(run.err).to include("no spec found for lib/people.rb (expected spec/people_spec.rb), so nothing ran")
      expect(run.err).to include("Re-run the same command with one --test per existing spec path")
      expect(run.err).to include("append --all to use the whole suite without changing the source scope")
      expect(run.err).not_to include("checking the unchanged suite")
    end

    it "stops before boot for a spec-less file even without --since" do
      without_reader
      run = saboteur(dir)
      expect(run.status).to eq(2)
      expect(run.err).to include("no spec found for lib/people.rb (expected spec/people_spec.rb), so nothing ran")
      expect(run.err).to include("append --all to use the whole suite without changing the source scope")
      expect(run.err).not_to include("checking the unchanged suite")
    end

    it "scopes --subject inference to the named subjects' files" do
      without_reader
      run = saboteur(dir, "--subject", "Stage", "--verbose")
      expect(run.status).to be <= 1
      expect(run.err).to include("inferred specs: running only spec/stage_spec.rb")
      expect(run.err).not_to include("no spec found for lib/people.rb, so nothing ran")

      run = saboteur(dir, "--subject", "People::Person#adult?")
      expect(run.status).to eq(2)
      expect(run.err).to include("no spec found for lib/people.rb (expected spec/people_spec.rb), so nothing ran")
    end

    it "rerun and replay from a config :all run with named tests carry no --all" do
      config = File.join(dir, "config", "saboteur.rb")
      File.write(config, File.read(config).sub("Saboteur.configure do |c|",
                                               "Saboteur.configure do |c|\n  c.test_selection = :all"))
      first = saboteur(dir, "--agent", "--test", "spec/stage_spec.rb")
      expect(first.status).to be <= 1
      payload = JSON.parse(first.out)
      %w[rerun replay].each do |key|
        command = payload.fetch("next").fetch(key, nil)
        next unless command

        words = Shellwords.split(command)
        expect(words).not_to include("--all")
        expect(saboteur(dir, *words[2..]).status).not_to eq(2)
      end
    end

    it "rerun and replay commands from an --all run execute as-is, even with a spec-less source" do
      first = saboteur(dir, "--all", "--agent")
      expect(first.status).to eq(1)
      payload = JSON.parse(first.out)
      rerun_words = Shellwords.split(payload.fetch("next").fetch("rerun"))
      expect(rerun_words).to include("--all")
      expect(saboteur(dir, *rerun_words[2..]).status).not_to eq(2)
      replay_words = Shellwords.split(payload.fetch("next").fetch("replay"))
      expect(saboteur(dir, *replay_words[2..]).status).not_to eq(2)
    end

    it "reports nothing to mutate when the changed lines carry no mutation subject" do
      path = File.join(dir, "lib", "people.rb")
      File.write(path, File.read(path).sub("@age = age", "# a note\n      @age = age"))
      run = saboteur(dir, "--since", "HEAD")
      expect(run.status).to eq(0)
      expect(run.err).to include("inferred specs: no changed file has a mutation subject on its changed lines, " \
                                 "so there is nothing to mutate")
      expect(run.out).to include("0 subjects, 0 mutants")
      expect(run.err).not_to include("checking the unchanged suite")
    end

    it "refuses conflicting selection flags" do
      run = saboteur(dir, "--since", "HEAD", "--guess-tests", "--test", "spec/stage_spec.rb")
      expect(run.err).to include("--guess-tests cannot be combined with --test")
      expect(saboteur(dir, "--all", "--test", "spec/stage_spec.rb").err)
        .to include("--all cannot be combined with --test")
      expect(saboteur(dir, "--all", "--guess-tests").err)
        .to include("--all cannot be combined with --guess-tests")
    end

    it "warns before an unscoped --since run what the loaded suite costs" do
      path = File.join(dir, "lib", "people.rb")
      File.write(path, File.read(path).sub("@age}", "@age.to_s}"))
      run = saboteur(dir, "--since", "HEAD", "--all", "--verbose")
      expect(run.err).to match(/running the loaded suite unscoped: \d+ examples in 3 spec files; \d+ full passes/)
      expect(run.err).to include("2 baseline checks + 1 coverage map build")
      expect(run.err).to match(/baseline check 1 took \d+ s; about \d+ s left for the remaining \d+ full pass(?:es)?/)
      expect(run.err.index("running the loaded suite unscoped")).to be < run.err.index("checking the unchanged suite")
    end
  end

  describe "--jobs" do
    it "gives the same verdicts with parallel workers as with one" do
      verdicts = ->(run) { mutants(run).to_h { |m| [m["id"], [m["status"], m["statusReason"]]] } }
      serial = saboteur(dir, "--all", "--jobs", "1")
      parallel = saboteur(dir, "--all", "--jobs", "3")
      expect(parallel.err).not_to include("not supported")
      one = verdicts.call(serial)
      many = verdicts.call(parallel)
      differing = one.keys.union(many.keys).reject { |id| one[id]&.first == many[id]&.first }
      expect(differing.to_h { |id| [id, { jobs1: one[id], jobs3: many[id] }] }).to eq({})
      expect(parallel.status).to eq(serial.status)
    end
  end

  describe "--incremental" do
    it "reuses every verdict when nothing changed, and re-runs what an edited spec file covers" do
      first = saboteur(dir, "--all", "--incremental", "--subject", "People::Person#adult?")
      total = mutants(first).size
      second = saboteur(dir, "--all", "--incremental", "--subject", "People::Person#adult?")
      expect(second.out).to include("reused #{total} of #{total} verdicts")
      expect(mutants(second).map { |m| m["status"] }).to eq(mutants(first).map { |m| m["status"] })

      spec_file = File.join(dir, "spec", "person_spec.rb")
      File.write(spec_file, "#{File.read(spec_file)}\n# edited\n")
      third = saboteur(dir, "--all", "--incremental", "--subject", "People::Person#adult?")
      expect(third.out).not_to include("reused #{total} of #{total}")
    end

    it "re-runs every verdict when a shared spec support file changes" do
      support = File.join(dir, "spec", "support", "helpers.rb")
      FileUtils.mkdir_p(File.dirname(support))
      File.write(support, "# helpers\n")
      saboteur(dir, "--all", "--incremental", "--subject", "People::Person#adult?")
      File.write(support, "# helpers, edited\n")
      after_edit = saboteur(dir, "--all", "--incremental", "--subject", "People::Person#adult?")
      expect(after_edit.out).not_to include("reused")
    end
  end

  describe "--resume" do
    let(:flags) { ["--all", "--resume", "state/run1", "--subject", "People::Person#adult?"] }

    it "creates the directory, reuses verdicts in the next run and refuses changed inputs (#471)" do
      first = saboteur(dir, *flags)
      total = mutants(first).size
      expect(File).to exist(File.join(dir, "state", "run1", "manifest.json"))
      expect(File).to exist(File.join(dir, "state", "run1", "results.json"))

      second = saboteur(dir, *flags)
      expect(second.out).to include("reused #{total} of #{total} verdicts")

      changed = saboteur(dir, *flags, "--seed", "2")
      expect(changed.status).to eq(2)
      expect(changed.err).to include("the run inputs changed since this directory was created")
    end
  end

  describe "ignore list" do
    def survivor_digests(run)
      mutants(run).select { |m| m["status"] == "Survived" }.map { |m| m["id"] }
    end

    it "exits 0 once every survivor is ignored with a reason, and reports them as ignored" do
      digests = survivor_digests(saboteur(dir, "--all", "--subject", "People::Person#adult?"))
      expect(digests).not_to be_empty
      lines = digests.map do |digest|
        %(  i.mutation "#{digest}", subject: "People::Person#adult?", reason: "boundary covered elsewhere")
      end
      File.write(File.join(dir, "config", "saboteur_ignore.rb"),
                 "Saboteur.ignore do |i|\n#{lines.join("\n")}\nend\n")

      run = saboteur(dir, "--all", "--subject", "People::Person#adult?")
      expect(run.status).to eq(0)
      expect(run.out).to include("#{digests.size} accepted", "ignored: boundary covered elsewhere")
      expect(mutants(run).select { |m| m["status"] == "Survived" }.map { |m| m["statusReason"] }.uniq)
        .to eq(["ignored: boundary covered elsewhere"])
    end

    it "refuses an entry without a reason (exit 2, before anything runs)" do
      File.write(File.join(dir, "config", "saboteur_ignore.rb"),
                 "Saboteur.ignore do |i|\n  i.mutation \"abc\", subject: \"People::Person#adult?\"\nend\n")
      run = saboteur(dir, "--all")
      expect(run.status).to eq(2)
      expect(run.err).not_to include("building coverage map")
      expect(run.err).to include("entry is missing reason")
    end
  end

  describe "config" do
    it "exits 2 for an invalid config file" do
      File.write(File.join(dir, "config", "saboteur.rb"), "Saboteur.configure { |c| c.timeout_factr = 2 }\n")
      run = saboteur(dir, "--all")
      expect(run.status).to eq(2)
      expect(run.err).to include('unknown setting "timeout_factr"')
    end

    it "lets CLI flags override the config file" do
      File.write(File.join(dir, "config", "saboteur.rb"),
                 "Saboteur.configure { |c| c.include = [\"lib/**/*.rb\"]; c.json_report = \"custom.json\" }\n")
      saboteur(dir, "--all", "--json", "flag.json")
      expect(File).to exist(File.join(dir, "flag.json"))
      expect(File).not_to exist(File.join(dir, "custom.json"))
    end

    it "writes valid JSON and an HTML report together, and keeps the survivor exit code" do
      run = saboteur(dir, "--all")
      expect(run.status).to eq(1), run.err
      expect(JSON.parse(File.read(File.join(dir, ".saboteur", "report.json")))["schemaVersion"]).to eq("2")
      expect(File.read(File.join(dir, ".saboteur", "report.html"))).to include("Covered mutation score", "Survived")
    end
  end
end
