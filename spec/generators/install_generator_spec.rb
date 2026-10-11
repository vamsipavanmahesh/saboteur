# SPDX-License-Identifier: MIT
# frozen_string_literal: true

# The generator is a thin wrapper; it is only exercised when Rails is
# installed. The behavior itself is covered in spec/saboteur/install_spec.rb.
RSpec.describe "saboteur:install generator" do
  it "is packaged where Rails looks for generators" do
    path = File.expand_path("../../lib/generators/saboteur/install/install_generator.rb", __dir__)
    expect(File.read(path)).to include("Saboteur::Install.new", "class InstallGenerator < Rails::Generators::Base")
  end

  it "is shipped in the gem files" do
    spec = Gem::Specification.load(File.expand_path("../../saboteur.gemspec", __dir__))
    expect(spec.files).to include("lib/generators/saboteur/install/install_generator.rb", "lib/saboteur/install.rb")
  end
end
