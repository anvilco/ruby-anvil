# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  add_filter "/spec/"
  enable_coverage :branch
  minimum_coverage line: 95, branch: 80
end

require "anvil"
require "webmock/rspec"

RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.include_chain_clauses_in_custom_matcher_descriptions = true }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.warnings = false
  config.order = :random
  Kernel.srand config.seed

  config.include(Module.new do
    # A client whose rate limiter is effectively open, so a spec that makes
    # several requests does not wait between them. The limiter's own behavior
    # is covered in rate_limiter_spec.rb and rate_limiting_spec.rb.
    def build_client(**overrides)
      Anvil::Client.new(
        api_key: "abc123", request_limit: 1000, request_limit_ms: 1, **overrides
      )
    end

    # The headers a real Anvil response carries, so the client's adaptive rate
    # limiting sees what it expects.
    def api_headers(extra = {})
      {
        "x-ratelimit-limit" => "10",
        "x-ratelimit-interval-ms" => "1000"
      }.merge(extra)
    end

    def json_headers(extra = {})
      api_headers({ "content-type" => "application/json; charset=utf-8" }.merge(extra))
    end

    def fixture_path(name)
      File.expand_path("fixtures/#{name}", __dir__)
    end
  end)
end
