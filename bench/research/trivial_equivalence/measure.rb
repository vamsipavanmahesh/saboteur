#!/usr/bin/env ruby
# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Measures how often a mutated file compiles to the same normalized
# instruction fingerprint as its original, on a real project.
#
#   ruby measure.rb --project DIR --files "lib/**/*.rb" --out result.json \
#        [--suite "rspec -I lib spec"] [--run-all] [--sample N] [--seed N] [--outcomes FILE]
#
# For every builtin saboteur mutation of every method in the files it asks
# the judge (strict and relaxed) for a fingerprint match. With --suite it
# runs the suite on each matched mutant (a failing suite is a wrong skip)
# and, with --run-all, on every mutant (with --sample N, on a seeded random
# N of them), so matches can be read against survival. A survivor is a mutant
# the suite did not kill; it is survival data, not proof of equivalence.
# --outcomes writes one JSON line per executed mutant. The project files are
# restored after every run, so point --project at a scratch copy.
require "json"
require "digest"
require "open3"
require "optparse"
require_relative "lib/trivial_equivalence"
$LOAD_PATH.unshift(File.expand_path("../../../lib", __dir__))
require "saboteur/subject_finder"
require "saboteur/mutation_source/builtin"

# Runs a suite command against one mutated copy of one project file.
class MutantSuiteRun
  def initialize(project:, suite_command:)
    @project = project
    @suite_command = suite_command
  end

  # Seconds before a hung suite (for example an endless loop in a mutant) is
  # stopped and counted as killed, the way a timeout counts as a kill.
  SUITE_TIMEOUT_SECONDS = 120

  # true when the suite fails or times out (the mutant is killed)
  def killed?(file, mutated_source)
    path = File.join(@project, file)
    original = File.binread(path)
    File.binwrite(path, mutated_source)
    _out, status = Open3.capture2e("timeout --signal=KILL #{SUITE_TIMEOUT_SECONDS} #{@suite_command}", chdir: @project)
    !status.success?
  ensure
    File.binwrite(path, original)
  end
end

original_arguments = ARGV.dup
options = { files: [], suite: nil, run_all: false, sample: nil, seed: 1, outcomes: nil }
OptionParser.new do |parser|
  parser.on("--project DIR") { |value| options[:project] = File.expand_path(value) }
  parser.on("--files GLOB") { |value| options[:files] << value }
  parser.on("--out FILE") { |value| options[:out] = value }
  parser.on("--suite CMD") { |value| options[:suite] = value }
  parser.on("--run-all") { options[:run_all] = true }
  parser.on("--sample N", Integer) { |value| options[:sample] = value }
  parser.on("--seed N", Integer) { |value| options[:seed] = value }
  parser.on("--outcomes FILE") { |value| options[:outcomes] = value }
end.parse!

# Where the inputs came from, so the counts can be reproduced.
# rubocop:disable-next Style/OneClassPerFile
module RunProvenance
  module_function

  def git_revision(directory)
    revision, _error, status = Open3.capture3("git", "-C", directory, "rev-parse", "HEAD")
    status.success? ? revision.strip : nil
  end

  def tool_version(command, directory)
    output, = Open3.capture2e(command, chdir: directory)
    output.lines.first(3).map(&:strip).join(" / ")
  end
end

project = options.fetch(:project)
files = options[:files].flat_map { |glob| Dir.glob(glob, base: project) }.sort
judges = { strict: TrivialEquivalence::EquivalenceJudge.new(level: :strict),
           relaxed: TrivialEquivalence::EquivalenceJudge.new(level: :relaxed) }
mutation_source = Saboteur::MutationSource::Builtin.new
finder = Saboteur::SubjectFinder.new
records = []
file_hashes = {}
accounting = { files_with_parse_errors: [], subjects_found: 0, subjects_skipped: Hash.new(0),
               files_without_subjects: 0 }

# rubocop:disable-next Metrics/BlockLength
files.each do |file|
  absolute = File.join(project, file)
  original = File.binread(absolute)
  file_hashes[file] = Digest::SHA256.hexdigest(original)
  parsed = finder.call(absolute)
  accounting[:files_with_parse_errors] << file unless parsed.errors.empty?
  accounting[:files_without_subjects] += 1 if parsed.subjects.empty?
  parsed.subjects.each do |subject|
    accounting[:subjects_found] += 1
    if subject.skip_reason
      accounting[:subjects_skipped][subject.skip_reason] += 1
      next
    end

    mutation_source.mutations_for(subject).each do |mutation|
      mutated = original.b
      mutation.edits.sort_by(&:start_byte).reverse_each do |edit|
        mutated = mutated.byteslice(0, edit.start_byte) + edit.replacement.b + mutated.byteslice(edit.end_byte..)
      end
      mutated.force_encoding(Encoding::UTF_8)
      verdicts = judges.transform_values do |judge|
        judge.judge(original_source: original.dup.force_encoding(Encoding::UTF_8), mutated_source: mutated, path: file)
      end
      identifier = mutation.digest(subject_start: subject.start_byte, original_source: original)
      records << { id: identifier, file: file, subject: subject.id, operator: mutation.operator,
                   strict: verdicts[:strict].status, strict_reason: verdicts[:strict].reason,
                   relaxed: verdicts[:relaxed].status, relaxed_reason: verdicts[:relaxed].reason,
                   mutated: mutated }
    end
  end
end

matched_by_any_level = ->(record) { %i[strict relaxed].any? { |level| record[level] == :fingerprint_match } }

if options[:suite]
  runner = MutantSuiteRun.new(project: project, suite_command: options[:suite])
  abort "baseline suite is not green" if runner.killed?(files.first, File.binread(File.join(project, files.first)))

  targets = records.select(&matched_by_any_level)
  targets |= records if options[:run_all]
  # The recorded sampling procedure: seeded shuffle, then take the first N.
  targets = targets.shuffle(random: Random.new(options[:seed])).first(options[:sample]) if options[:sample] # rubocop:disable Style/Sample
  targets.each { |record| record[:killed] = runner.killed?(record[:file], record[:mutated]) }
end

summary = lambda do |level|
  matched = records.select { |record| record[level] == :fingerprint_match }
  checked = matched.reject { |record| record[:killed].nil? }
  { matched: matched.size, matched_and_run_against_suite: checked.size,
    matched_but_killed: checked.count { |record| record[:killed] },
    reasons: records.group_by { |record| record[:"#{level}_reason"] }.transform_values(&:size) }
end

executed = records.reject { |record| record[:killed].nil? }
if options[:outcomes]
  lines = executed.map { |record| JSON.generate(record.except(:mutated)) }
  File.write(options[:outcomes], "#{lines.join("\n")}\n")
end
result = {
  compiler: TrivialEquivalence::CompilerPin.description,
  provenance: {
    command: ["ruby", "measure.rb", *original_arguments], ruby: RUBY_DESCRIPTION, prism: Prism::VERSION,
    project_git_revision: RunProvenance.git_revision(project),
    saboteur_git_revision: RunProvenance.git_revision(File.expand_path("../../..", __dir__)),
    suite_tool: options[:suite] && RunProvenance.tool_version("#{options[:suite].split.first} --version", project),
    file_sha256: file_hashes, accounting: accounting
  },
  project: File.basename(project), files: files.size, mutants: records.size,
  strict: summary.call(:strict), relaxed: summary.call(:relaxed),
  executed_mutants: executed.size, survivors_among_executed: executed.count { |record| !record[:killed] },
  executed_all: options[:run_all] && options[:sample].nil?,
  matched_but_killed_examples: records.select { |record| matched_by_any_level.call(record) && record[:killed] }
                                      .first(10).map { |record| record.except(:mutated) }
}
File.write(options.fetch(:out), JSON.pretty_generate(result))
puts JSON.pretty_generate(result.except(:provenance))
