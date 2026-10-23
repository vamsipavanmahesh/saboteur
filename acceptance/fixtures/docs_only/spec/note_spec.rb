require_relative "../lib/note"

RSpec.describe Note do
  it("has text") { expect(Note.text).to eq("hi") }
end
