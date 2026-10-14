# SPDX-License-Identifier: MIT
# frozen_string_literal: true

RSpec.describe "private module-function mutation", :e2e do
  it "kills private helper mutations through the public contract and keeps the helper private" do
    dir = copy_fixture("people")
    File.open(File.join(dir, "lib/people.rb"), "a") do |file|
      file.puts <<~RUBY
        module PrivateModuleProbe
          module_function
          def secret(a)
            a + 1
          end
          private_class_method :secret
          def value(a)
            secret(a)
          end
        end
      RUBY
    end
    File.write(File.join(dir, "spec/private_module_spec.rb"), <<~RUBY)
      require_relative "../lib/people"
      RSpec.describe PrivateModuleProbe do
        it("uses its private helper") do
          expect(PrivateModuleProbe.value(2)).to eq(3)
          expect(PrivateModuleProbe.singleton_class.private_method_defined?(:secret, false)).to be(true)
        end
      end
    RUBY
    run = saboteur(dir, "--all", "--subject", "PrivateModuleProbe#secret")
    expect(run.status).to eq(0), run.err
    expect(mutants(run)).not_to be_empty
    expect(mutants(run).map { |item| item["status"] }.uniq).to eq(["Killed"])
  end
end
