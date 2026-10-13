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
      run = saboteur(dir, "--since", "HEAD")
      expect(subject_lines(run)).to eq([31])
      expect(run.out).to include("1 subjects")
    end

    it "mutates only the changed lines of a changed method, plus its coarse mutants" do
      path = File.join(dir, "lib", "stage.rb")
      File.write(path, File.read(path).sub("label.upcase", "label.downcase"))
      run = saboteur(dir, "--since", "HEAD")
      fine = mutants(run).reject { |m| m["mutatorName"].start_with?("body_") }
      expect(fine.map { |m| m["location"]["start"]["line"] }.uniq).to eq([10])
      expect(mutants(run).map { |m| m["mutatorName"] }).to include("body_nil", "body_raise")
    end

    it "mutates nothing and exits 0 when nothing changed" do
      run = saboteur(dir, "--since", "HEAD")
      expect(run.status).to eq(0)
      expect(run.out).to include("0 subjects, 0 mutants")
    end

    it "exits 3 for an unknown ref" do
      run = saboteur(dir, "--since", "no-such-ref")
      expect(run.status).to eq(3)
      expect(run.err).to include("git merge-base failed")
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

    it "scopes to the specs named after the changed files with --guess-tests" do
      path = File.join(dir, "lib", "stage.rb")
      File.write(path, File.read(path).sub("label.upcase", "label.downcase"))
      run = saboteur(dir, "--since", "HEAD", "--guess-tests")
      expect(run.status).to be_between(0, 1)
      expect(run.err).to include("--guess-tests: running only spec/stage_spec.rb.")
      expect(run.err).to include("building coverage map (runs the selected specs once)")
      expect(run.err).not_to include("running the loaded suite unscoped")
    end

    it "records the guessed specs in agent provenance and reports uncovered mutants as no coverage" do
      path = File.join(dir, "lib", "stage.rb")
      File.write(path, File.read(path).sub("label.upcase", "label.downcase"))
      run = saboteur(dir, "--since", "HEAD", "--guess-tests", "--agent")
      expect(run.err).to include("is reported as NoCoverage")
      payload = JSON.parse(run.out)
      expect(payload.dig("provenance", "selection", "tests", "first")).to eq(["spec/stage_spec.rb"])
      expect(payload.fetch("incomplete").map { |reason| reason["reason"] }).to include("no_coverage")
      expect(JSON.generate(payload.fetch("next", {}))).not_to include("--guess-tests")
    end

    it "runs the whole suite when a changed file has no spec named after it" do
      path = File.join(dir, "lib", "people.rb")
      File.write(path, File.read(path).sub("@age}", "@age.to_s}"))
      run = saboteur(dir, "--since", "HEAD", "--guess-tests")
      expect(run.err).to include("--guess-tests: no spec found for lib/people.rb, so the whole suite runs")
      expect(run.err).to include("running the loaded suite unscoped")
    end

    it "refuses --guess-tests without --since or together with --test" do
      expect(saboteur(dir, "--guess-tests").err).to include("guess_tests needs since")
      run = saboteur(dir, "--since", "HEAD", "--guess-tests", "--test", "spec/stage_spec.rb")
      expect(run.err).to include("guess_tests cannot be combined with tests")
    end

    it "warns before an unscoped --since run what the loaded suite costs" do
      path = File.join(dir, "lib", "people.rb")
      File.write(path, File.read(path).sub("@age}", "@age.to_s}"))
      run = saboteur(dir, "--since", "HEAD")
      warning = "running the loaded suite unscoped: two baseline passes; coverage may add a pass (3 spec files). " \
                "Pass --test to run only the specs you name: faster, but a mutant of a changed method is then killed " \
                "only by those specs, so specs elsewhere that call this code are not run. " \
                "--guess-tests does the same with the specs named after the changed files, " \
                "a guess that can miss specs elsewhere."
      expect(run.err).to include(warning)
      expect(run.err.index("running the loaded suite unscoped")).to be < run.err.index("checking the unchanged suite")
    end
  end

  describe "--jobs" do
    it "gives the same verdicts with parallel workers as with one" do
      verdicts = ->(run) { mutants(run).to_h { |m| [m["id"], [m["status"], m["statusReason"]]] } }
      serial = saboteur(dir, "--jobs", "1")
      parallel = saboteur(dir, "--jobs", "3")
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
      first = saboteur(dir, "--incremental", "--subject", "People::Person#adult?")
      total = mutants(first).size
      second = saboteur(dir, "--incremental", "--subject", "People::Person#adult?")
      expect(second.out).to include("reused #{total} of #{total} verdicts")
      expect(mutants(second).map { |m| m["status"] }).to eq(mutants(first).map { |m| m["status"] })

      spec_file = File.join(dir, "spec", "person_spec.rb")
      File.write(spec_file, "#{File.read(spec_file)}\n# edited\n")
      third = saboteur(dir, "--incremental", "--subject", "People::Person#adult?")
      expect(third.out).not_to include("reused #{total} of #{total}")
    end

    it "re-runs every verdict when a shared spec support file changes" do
      support = File.join(dir, "spec", "support", "helpers.rb")
      FileUtils.mkdir_p(File.dirname(support))
      File.write(support, "# helpers\n")
      saboteur(dir, "--incremental", "--subject", "People::Person#adult?")
      File.write(support, "# helpers, edited\n")
      after_edit = saboteur(dir, "--incremental", "--subject", "People::Person#adult?")
      expect(after_edit.out).not_to include("reused")
    end
  end

  describe "ignore list" do
    def survivor_digests(run)
      mutants(run).select { |m| m["status"] == "Survived" }.map { |m| m["id"] }
    end

    it "exits 0 once every survivor is ignored with a reason, and reports them as ignored" do
      digests = survivor_digests(saboteur(dir, "--subject", "People::Person#adult?"))
      expect(digests).not_to be_empty
      lines = digests.map do |digest|
        %(  i.mutation "#{digest}", subject: "People::Person#adult?", reason: "boundary covered elsewhere")
      end
      File.write(File.join(dir, "config", "saboteur_ignore.rb"),
                 "Saboteur.ignore do |i|\n#{lines.join("\n")}\nend\n")

      run = saboteur(dir, "--subject", "People::Person#adult?")
      expect(run.status).to eq(0)
      expect(run.out).to include("(#{digests.size} ignored)", "ignored: boundary covered elsewhere")
      expect(mutants(run).select { |m| m["status"] == "Survived" }.map { |m| m["statusReason"] }.uniq)
        .to eq(["ignored: boundary covered elsewhere"])
    end

    it "refuses an entry without a reason (exit 2, before anything runs)" do
      File.write(File.join(dir, "config", "saboteur_ignore.rb"),
                 "Saboteur.ignore do |i|\n  i.mutation \"abc\", subject: \"People::Person#adult?\"\nend\n")
      run = saboteur(dir)
      expect(run.status).to eq(2)
      expect(run.err).not_to include("building coverage map")
      expect(run.err).to include("entry is missing reason")
    end
  end

  describe "config" do
    it "exits 2 for an invalid config file" do
      File.write(File.join(dir, "config", "saboteur.rb"), "Saboteur.configure { |c| c.timeout_factr = 2 }\n")
      run = saboteur(dir)
      expect(run.status).to eq(2)
      expect(run.err).to include('unknown setting "timeout_factr"')
    end

    it "lets CLI flags override the config file" do
      File.write(File.join(dir, "config", "saboteur.rb"),
                 "Saboteur.configure { |c| c.include = [\"lib/**/*.rb\"]; c.json_report = \"custom.json\" }\n")
      saboteur(dir, "--json", "flag.json")
      expect(File).to exist(File.join(dir, "flag.json"))
      expect(File).not_to exist(File.join(dir, "custom.json"))
    end

    it "writes valid JSON and an HTML report together, and keeps the survivor exit code" do
      run = saboteur(dir)
      expect(run.status).to eq(1), run.err
      expect(JSON.parse(File.read(File.join(dir, ".saboteur", "report.json")))["schemaVersion"]).to eq("2")
      expect(File.read(File.join(dir, ".saboteur", "report.html"))).to include("Covered mutation score", "Survived")
    end
  end
end
