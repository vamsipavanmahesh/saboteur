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
      File.write(path, File.read(path).sub('"age ', '"aged '))
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
      entries = digests.map do |digest|
        { "subject" => "People::Person#adult?", "mutation" => digest, "reason" => "boundary covered elsewhere" }
      end
      File.write(File.join(dir, ".saboteur-ignore.yml"), entries.to_yaml)

      run = saboteur(dir, "--subject", "People::Person#adult?")
      expect(run.status).to eq(0)
      expect(run.out).to include("(#{digests.size} ignored)", "ignored: boundary covered elsewhere")
      expect(mutants(run).select { |m| m["status"] == "Survived" }.map { |m| m["statusReason"] }.uniq)
        .to eq(["ignored: boundary covered elsewhere"])
    end

    it "refuses an entry without a reason (exit 2, before anything runs)" do
      File.write(File.join(dir, ".saboteur-ignore.yml"), "- subject: People::Person#adult?\n  mutation: abc\n")
      run = saboteur(dir)
      expect(run.status).to eq(2)
      expect(run.err).not_to include("building coverage map")
      expect(run.err).to include("entry 1 is missing reason")
    end
  end

  describe "config" do
    it "exits 2 for an invalid config file" do
      File.write(File.join(dir, ".saboteur.yml"), "timeout_factr: 2\n")
      run = saboteur(dir)
      expect(run.status).to eq(2)
      expect(run.err).to include("unknown config key(s): timeout_factr")
    end

    it "lets CLI flags override the config file" do
      File.write(File.join(dir, ".saboteur.yml"), "include: [lib/**/*.rb]\njson_report: custom.json\n")
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
