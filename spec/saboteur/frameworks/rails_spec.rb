# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe Saboteur::Frameworks::Rails do
  describe ".worker_database" do
    it "keeps the first worker on the test database and numbers the rest like parallel tests" do
      expect((0..2).map { |n| described_class.worker_database("app_test", n) })
        .to eq(%w[app_test app_test2 app_test3])
    end

    it "numbers SQLite files before their extension" do
      expect(described_class.worker_database("db/test.sqlite3", 1)).to eq("db/test2.sqlite3")
    end
  end

  describe ".local_host?" do
    it "accepts local hosts and sockets only" do
      expect(%w[localhost 127.0.0.1 ::1 /tmp/pg].map { |h| described_class.local_host?(h) }).to all(be(true))
      expect([nil, ""].map { |h| described_class.local_host?(h) }).to all(be(true))
      expect(described_class.local_host?("db.example.com")).to be(false)
    end
  end
end
