# frozen_string_literal: true

RSpec.describe "Anvil::Client rate limiting" do
  def stub_generate_pdf(*responses)
    stub_request(:post, "https://app.useanvil.com/api/v1/generate-pdf").to_return(*responses)
  end

  def ok(headers = {})
    { status: 200, body: "%PDF", headers: api_headers(headers) }
  end

  describe "the limiter the client starts with" do
    it "allows one request a second until the API says otherwise" do
      client = Anvil::Client.new(api_key: "abc123")

      expect(client.rate_limiter.tokens).to eq(Anvil::Client::DEFAULT_REQUEST_LIMIT)
      expect(client.rate_limiter.interval_ms).to eq(Anvil::Client::DEFAULT_REQUEST_LIMIT_MS)
    end

    it "can be configured" do
      client = Anvil::Client.new(api_key: "abc123", request_limit: 5, request_limit_ms: 250)

      expect(client.rate_limiter.tokens).to eq(5)
      expect(client.rate_limiter.interval_ms).to eq(250)
    end

    it "takes a token for each request" do
      client = build_client
      stub_generate_pdf(ok)
      before = client.rate_limiter.tokens_remaining

      client.generate_pdf(type: "html", data: {})

      expect(client.rate_limiter.tokens_remaining).to be <= before
    end
  end

  describe "adopting the API's own limit" do
    it "rebuilds the limiter from the first response's headers" do
      client = build_client
      stub_generate_pdf(ok("x-ratelimit-limit" => "42", "x-ratelimit-interval-ms" => "4200"))

      client.generate_pdf(type: "html", data: {})

      expect(client.rate_limiter.tokens).to eq(42)
      expect(client.rate_limiter.interval_ms).to eq(4200)
    end

    it "carries the spent tokens over, so resizing hands out no free burst" do
      client = Anvil::Client.new(api_key: "abc123", request_limit: 1, request_limit_ms: 60_000)
      stub_generate_pdf(ok("x-ratelimit-limit" => "42", "x-ratelimit-interval-ms" => "60000"))

      client.generate_pdf(type: "html", data: {})

      # The one token the request spent is spent in the new bucket too
      expect(client.rate_limiter.tokens_remaining).to be_within(0.5).of(41)
    end

    it "only does it once, however the later responses are headed" do
      client = build_client
      stub_generate_pdf(
        ok("x-ratelimit-limit" => "42", "x-ratelimit-interval-ms" => "4200"),
        ok("x-ratelimit-limit" => "7", "x-ratelimit-interval-ms" => "1000")
      )

      client.generate_pdf(type: "html", data: {})
      client.generate_pdf(type: "html", data: {})

      expect(client.rate_limiter.tokens).to eq(42)
      expect(client.rate_limiter.interval_ms).to eq(4200)
    end

    it "keeps the limiter it has when the headers are missing" do
      client = build_client
      stub_generate_pdf(status: 200, body: "%PDF", headers: {})

      client.generate_pdf(type: "html", data: {})

      expect(client.rate_limiter.tokens).to eq(1000)
    end

    it "keeps the limiter it has when the headers are nonsense" do
      client = build_client
      stub_generate_pdf(ok("x-ratelimit-limit" => "not a number", "x-ratelimit-interval-ms" => "0"))

      client.generate_pdf(type: "html", data: {})

      expect(client.rate_limiter.tokens).to eq(1000)
    end
  end

  describe "a 429 response" do
    let(:client) { build_client }

    before { allow(client).to receive(:sleep) }

    it "is retried after the delay the API asks for, plus a 50ms buffer" do
      stub_generate_pdf(
        { status: 429, headers: api_headers("retry-after" => "0.2") },
        ok
      )

      response = client.generate_pdf(type: "html", data: {})

      expect(response.data).to eq("%PDF")
      expect(client).to have_received(:sleep).with(0.25).once
    end

    it "rounds the delay to whole milliseconds, the way node-anvil does" do
      stub_generate_pdf({ status: 429, headers: api_headers("retry-after" => "1.2345") }, ok)

      client.generate_pdf(type: "html", data: {})

      expect(client).to have_received(:sleep).with(1.285)
    end

    it "waits only the buffer when the API names no delay" do
      stub_generate_pdf({ status: 429, headers: api_headers }, ok)

      client.generate_pdf(type: "html", data: {})

      expect(client).to have_received(:sleep).with(0.05)
    end

    it "treats a negative delay as its own magnitude" do
      stub_generate_pdf({ status: 429, headers: api_headers("retry-after" => "-2") }, ok)

      client.generate_pdf(type: "html", data: {})

      expect(client).to have_received(:sleep).with(2.05)
    end

    it "gives up after max_retries, and says how long it was asked to wait" do
      limited = build_client(max_retries: 2)
      allow(limited).to receive(:sleep)
      stub_generate_pdf({ status: 429, headers: api_headers("retry-after" => "0.1") })

      expect { limited.generate_pdf(type: "html", data: {}) }
        .to raise_error(Anvil::RateLimitError) do |error|
          expect(error.status_code).to eq(429)
          expect(error.retry_after).to eq(0.1)
          expect(error.message).to include("Retry after 0.1 seconds")
        end

      expect(limited).to have_received(:sleep).twice
    end

    it "does not retry at all when max_retries is zero" do
      never = build_client(max_retries: 0)
      allow(never).to receive(:sleep)
      stub_generate_pdf({ status: 429, headers: api_headers("retry-after" => "0.1") }, ok)

      expect { never.generate_pdf(type: "html", data: {}) }.to raise_error(Anvil::RateLimitError)
      expect(never).not_to have_received(:sleep)
    end

    it "retries a GraphQL request too" do
      stub_request(:post, "https://app.useanvil.com/graphql").to_return(
        { status: 429, headers: api_headers("retry-after" => "0.1") },
        { status: 200, body: '{"data":{"removeWeldData":true}}', headers: json_headers }
      )

      expect(client.remove_weld_data(eid: "weld123")).to be(true)
      expect(client).to have_received(:sleep).with(0.15)
    end
  end
end
