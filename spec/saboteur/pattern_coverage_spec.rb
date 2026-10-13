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
  it "handles an empty method without pattern evidence" do
    empty = subjects_in("class EmptyPattern\n  def m\n  end\nend\n").first
    edit = Saboteur::MutationSource::Edit.new(file: empty.file, start_byte: empty.start_byte,
                                              end_byte: empty.end_byte, replacement: "nil")
    expect(empty.coverage_lines_for(edit)).to eq(empty.coverage_lines)
  end

  it "maps empty pattern clauses without assuming a body exists" do
    empty = subjects_in("class EmptyClause\n  def m(x)\n    case x\n    in 1\n    end\n  end\nend\n").first
    offset = empty.file_source.index("1")
    edit = Saboteur::MutationSource::Edit.new(file: empty.file, start_byte: offset, end_byte: offset + 1,
                                              replacement: "2")
    expect(empty.coverage_lines_for(edit)).to eq([3, 4])
  end

  it "finds a case nested after another expression in a call" do
    nested = subjects_in(<<~RUBY).first
      class NestedPattern
        def m(x)
          other.call(case x
                     in 1
                       2
                     end)
        end
      end
    RUBY
    offset = nested.file_source.index("1")
    edit = Saboteur::MutationSource::Edit.new(file: nested.file, start_byte: offset, end_byte: offset + 1,
                                              replacement: "2")
    expect(nested.coverage_lines_for(edit)).to eq([3, 4, 5])
  end

  it "includes edits exactly at either node boundary but excludes outside edits" do
    child = target.node.body
    first = child.location.start_offset
    last = child.location.end_offset
    [[first, last, true], [first - 1, last, false], [first, last + 1, false]].each do |start_byte, end_byte, inside|
      edit = Saboteur::MutationSource::Edit.new(file: target.file, start_byte: start_byte, end_byte: end_byte,
                                                replacement: "nil")
      expect(target.send(:contains_edit?, child, edit)).to eq(inside)
    end
  end
end
