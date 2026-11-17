# frozen_string_literal: true

require_relative "lib/anvil/version"

Gem::Specification.new do |spec|
  spec.name = "ruby-anvil"
  spec.version = Anvil::VERSION
  spec.authors = ["Anvil Foundry Inc."]
  spec.email = ["support@useanvil.com"]

  spec.summary = "Anvil API client for Ruby"
  spec.description = "Fill PDFs, generate PDFs from HTML or markdown, send documents for e-signature, " \
                     "and run Workflows with the Anvil API."
  spec.homepage = "https://github.com/anvilco/ruby-anvil"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://www.useanvil.com/docs/api/getting-started"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb"] + %w[README.md CHANGELOG.md LICENSE.txt]
  spec.require_paths = ["lib"]

  # The client is built on the standard library alone: no runtime dependencies.
end
