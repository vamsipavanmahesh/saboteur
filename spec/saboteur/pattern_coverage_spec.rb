# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Subject, "pattern coverage" do
  let(:target) do
    subjects_in(<<~RUBY).first
      class PatternCoverage
        def route(event)
          case event
          in {type: "charge"}
            :charged
          in {type: "refund"}
            :refunded
          else
            :unknown
          end
        end
      end
    RUBY
  end

  def edit_at(text)
    offset = target.file_source.index(text)
    Saboteur::MutationSource::Edit.new(file: target.file, start_byte: offset,
                                       end_byte: offset + text.bytesize, replacement: "nil")
  end

  it "uses the enclosing case, clause header and body for pattern edits" do
    expect(target.coverage_lines_for(edit_at('"charge"'))).to eq([3, 4, 5])
    expect(target.coverage_lines_for(edit_at('"refund"'))).to eq([3, 6, 7])
  end

  it "selects a pattern when only its body has line events" do
    map = Saboteur::Selection::CoverageMap.new(lines: { target.file => { 5 => ["charge"], 7 => ["refund"] } },
                                               tests: %w[charge refund])
    expect(map.tests_for_edit(target, target.coverage_lines_for(edit_at('"charge"')))).to eq(["charge"])
    expect(map.tests_for_edit(target, target.coverage_lines_for(edit_at('"refund"')))).to eq(["refund"])
  end

  it "does not widen an edit in an untested body or else branch" do
    expect(target.coverage_lines_for(edit_at(":refunded"))).to eq([7])
    expect(target.coverage_lines_for(edit_at(":unknown"))).to eq([9])
  end
end
