#!/usr/bin/env ruby
# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# Measures trivial-compiler-equivalence on a real project.
#
#   ruby measure.rb --project DIR --files "lib/**/*.rb" --out result.json \
#        [--suite "rspec -I lib spec"] [--run-all] [--sample N]
#
# For every builtin saboteur mutation of every method in the files it asks
# the judge (strict and relaxed) whether the mutated file compiles to the
# same instruction sequence. With --suite it then runs the suite on each
# proven-equivalent mutant (a failing suite is a wrong skip) and, with
# --run-all, on every mutant (so hit rate can be read against survivors).
# The project files are restored after every run.
require "json"
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

  # true when the suite fails (the mutant is killed)
  def killed?(file, mutated_source)
    path = File.join(@project, file)
    original = File.binread(path)
    File.binwrite(path, mutated_source)
    _out, status = Open3.capture2e(@suite_command, chdir: @project)
    !status.success?
  ensure
    File.binwrite(path, original)
  end
end

options = { files: [], suite: nil, run_all: false, sample: nil, seed: 1 }
OptionParser.new do |parser|
  parser.on("--project DIR") { |value| options[:project] = File.expand_path(value) }
  parser.on("--files GLOB") { |value| options[:files] << value }
  parser.on("--out FILE") { |value| options[:out] = value }
  parser.on("--suite CMD") { |value| options[:suite] = value }
  parser.on("--run-all") { options[:run_all] = true }
  parser.on("--sample N", Integer) { |value| options[:sample] = value }
  parser.on("--seed N", Integer) { |value| options[:seed] = value }
end.parse!

project = options.fetch(:project)
files = options[:files].flat_map { |glob| Dir.glob(glob, base: project) }.sort
judges = { strict: TrivialEquivalence::EquivalenceJudge.new(level: :strict),
           relaxed: TrivialEquivalence::EquivalenceJudge.new(level: :relaxed) }
source_for_mutations = Saboteur::MutationSource::Builtin.new
finder = Saboteur::SubjectFinder.new
records = []

files.each do |file|
  absolute = File.join(project, file)
  original = File.binread(absolute)
  parsed = finder.call(absolute)
  parsed.subjects.each do |subject|
    next if subject.skip_reason

    source_for_mutations.mutations_for(subject).each do |mutation|
      mutated = original.b
      mutation.edits.sort_by(&:start_byte).reverse_each do |edit|
        mutated = mutated.byteslice(0, edit.start_byte) + edit.replacement.b + mutated.byteslice(edit.end_byte..)
      end
      mutated.force_encoding(Encoding::UTF_8)
      verdicts = judges.transform_values do |judge|
        judge.judge(original_source: original.dup.force_encoding(Encoding::UTF_8), mutated_source: mutated, path: file)
      end
      records << { file: file, subject: subject.id, operator: mutation.operator, coarse: mutation.coarse,
                   strict: verdicts[:strict].status, strict_reason: verdicts[:strict].reason,
                   relaxed: verdicts[:relaxed].status, relaxed_reason: verdicts[:relaxed].reason,
                   mutated: mutated }
    end
  end
end

if options[:suite]
  runner = MutantSuiteRun.new(project: project, suite_command: options[:suite])
  baseline_killed = runner.killed?(files.first, File.binread(File.join(project, files.first)))
  abort "baseline suite is not green" if baseline_killed

  targets = records.select { |record| record[:strict] == :proven_equivalent || record[:relaxed] == :proven_equivalent }
  targets |= records if options[:run_all]
  # The recorded sampling procedure: seeded shuffle, then take the first N.
  targets = targets.shuffle(random: Random.new(options[:seed])).first(options[:sample]) if options[:sample] # rubocop:disable Style/Sample
  targets.each { |record| record[:killed] = runner.killed?(record[:file], record[:mutated]) }
end

summary = lambda do |level|
  proven = records.select { |record| record[level] == :proven_equivalent }
  checked = proven.reject { |record| record[:killed].nil? }
  { proven: proven.size, proven_checked_by_suite: checked.size,
    wrong_skips: checked.count { |record| record[:killed] },
    reasons: records.group_by { |record| record[:"#{level}_reason"] }.transform_values(&:size) }
end

proven_by_any_level = ->(record) { %i[strict relaxed].any? { |level| record[level] == :proven_equivalent } }
executed = records.reject { |record| record[:killed].nil? }
result = {
  compiler: TrivialEquivalence::CompilerPin.description, project: project, files: files.size,
  mutants: records.size, strict: summary.call(:strict), relaxed: summary.call(:relaxed),
  by_operator_proven_relaxed: records.select { |record| record[:relaxed] == :proven_equivalent }
                                     .group_by { |record| record[:operator] }.transform_values(&:size),
  executed_mutants: executed.size, survivors_among_executed: executed.count { |record| !record[:killed] },
  executed_all: options[:run_all] && options[:sample].nil?,
  wrong_skip_examples: records.select { |record| proven_by_any_level.call(record) && record[:killed] }
                              .first(10).map { |record| record.except(:mutated) }
}
File.write(options.fetch(:out), JSON.pretty_generate(result))
puts JSON.pretty_generate(result)
