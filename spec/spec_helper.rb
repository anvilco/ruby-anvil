# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  add_filter "/spec/"
  enable_coverage :branch
  minimum_coverage line: 95, branch: 80
end

require "anvil"
require "timeout"
require "webmock/rspec"

RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.include_chain_clauses_in_custom_matcher_descriptions = true }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.warnings = false
  config.order = :random
  Kernel.srand config.seed

  # The rate limiter makes callers wait, so a bug in it deadlocks rather than
  # fails. Nothing here legitimately takes a second, so bound every example and
  # let a deadlock surface as a failure with a backtrace.
  config.around do |example|
    Timeout.timeout(10) { example.run }
  rescue Timeout::Error
    raise "Example timed out after 10s, which usually means a deadlock in the rate limiter"
  end

  config.include(Module.new do
    # Its own open limiter, so examples neither wait nor leak into each other; CONTRIBUTING.md has the detail
    def build_client(**overrides)
      Anvil::Client.new(
        api_key: "abc123",
        request_limit: 1000,
        request_limit_ms: 1,
        share_rate_limiter: false,
        **overrides
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
