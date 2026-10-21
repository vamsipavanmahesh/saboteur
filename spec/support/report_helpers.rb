# SPDX-License-Identifier: MIT
# frozen_string_literal: true

module ReportHelpers
  PERSON = <<~RUBY
    class Person
      def adult?; @age >= 18; end
    end
  RUBY

  def person_subject
    @person_subject ||= subjects_in(PERSON, name: "person.rb").first
  end

  def comparison_mutation(replacement: ">", coarse: false)
    at = person_subject.file_source.index(">=")
    edit = Saboteur::MutationSource::Edit.new(file: person_subject.file, start_byte: at, end_byte: at + 2,
                                              replacement:)
    operator = coarse ? "body_nil" : "comparison"
    Saboteur::MutationSource::Mutation.new(subject_id: person_subject.id, operator:, edits: [edit], coarse:)
  end

  def result_for(status, replacement: ">", coarse: false, operator: nil, **)
    mutation = comparison_mutation(replacement:, coarse:)
    mutation = mutation.with(operator:) if operator
    Saboteur::MutantResult.new(subject: person_subject, mutation:, status:,
                               mutated_source: person_subject.apply(mutation.edits), **)
  end

  def report_of(*results, warnings: [], live_announced: [], policy: nil, memory: nil, referenced: {},
                skipped_subjects: {}, reuse_label: nil)
    Saboteur::Report.new(results:, subjects: [person_subject], wall_time: 1.25,
                         root: File.dirname(person_subject.file), warnings:, live_announced:, seed: 1, memory:,
                         referenced:, skipped_subjects:, reuse_label:,
                         operator_policy: policy || Saboteur::Config.new({}).operator_policy)
  end
end

RSpec.configure { |config| config.include ReportHelpers }
