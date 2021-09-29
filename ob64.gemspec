# frozen_string_literal: true

require "date"
require_relative "lib/ob64/version"

Gem::Specification.new do |spec|
  spec.name = "ob64"
  spec.version = Ob64::VERSION
  spec.authors = ["João Fernandes"]
  spec.email = ["joao.fernandes@ist.utl.pt"]
  spec.homepage = "https://github.com/jcmfernandes/ob64"
  spec.license = "MIT"
  spec.summary = "A fast Base64 encoder and decoder."
  spec.description = "A fast Base64 encoder and decoder that makes use of SIMD extensions."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end + Dir.chdir(File.join(File.expand_path(__dir__), "vendor", "libbase64")) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }.map! { |f| "vendor/libbase64/#{f}" }
  end
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/ob64/extconf.rb"]

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "changelog_uri" => spec.homepage + "/blob/master/CHANGELOG.md",
    "documentation_uri" => "https://www.rubydoc.info/gems/ob64/#{spec.version}",
    "source_code_uri" => spec.homepage + "/tree/v#{spec.version}"
  }

  spec.required_ruby_version = Gem::Requirement.new(">= 2.5.0")
end
