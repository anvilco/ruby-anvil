# frozen_string_literal: true

RSpec.describe "Anvil::Client rate limiting and retries" do
  def stub_generate_pdf(*responses)
    stub_request(:post, "https://app.useanvil.com/api/v1/generate-pdf").to_return(*responses)
  end

  def ok(headers = {})
    { status: 200, body: "%PDF", headers: api_headers(headers) }
  end

  def generate_pdf(client)
    client.generate_pdf(type: "html", data: {})
  end

  describe "the limiter a client gets" do
    it "starts at one request a second, below any real limit" do
      client = Anvil::Client.new(api_key: "abc123", share_rate_limiter: false)

      expect(client.rate_limiter.limit).to eq(Anvil::Client::DEFAULT_REQUEST_LIMIT)
      expect(client.rate_limiter.interval_ms).to eq(Anvil::Client::DEFAULT_REQUEST_LIMIT_MS)
    end

    it "is shared with every other client for the same environment and credentials" do
      one = Anvil::Client.new(api_key: "shared-key", base_url: "https://staging.useanvil.com")
      two = Anvil::Client.new(api_key: "shared-key", base_url: "https://staging.useanvil.com")

      expect(one.rate_limiter).to be(two.rate_limiter)
    end

    it "is not shared across credentials or environments" do
      base = Anvil::Client.new(api_key: "key-one", base_url: "https://staging.useanvil.com")
      other_key = Anvil::Client.new(api_key: "key-two", base_url: "https://staging.useanvil.com")
      other_env = Anvil::Client.new(api_key: "key-one", base_url: "https://app.useanvil.com")

      expect(base.rate_limiter).not_to be(other_key.rate_limiter)
      expect(base.rate_limiter).not_to be(other_env.rate_limiter)
    end

    it "is the client's own when sharing is turned off" do
      one = Anvil::Client.new(api_key: "solo-key", share_rate_limiter: false)
      two = Anvil::Client.new(api_key: "solo-key", share_rate_limiter: false)

      expect(one.rate_limiter).not_to be(two.rate_limiter)
    end

    it "can be one you built yourself" do
      mine = Anvil::RateLimiter.new(limit: 7, interval_ms: 700)

      expect(Anvil::Client.new(api_key: "abc123", rate_limiter: mine).rate_limiter).to be(mine)
    end
  end

  describe "adopting the API's own limit" do
    it "takes it from the first response's headers" do
      client = build_client
      stub_generate_pdf(ok("x-ratelimit-limit" => "42", "x-ratelimit-interval-ms" => "4200"))

      generate_pdf(client)

      expect(client.rate_limiter.limit).to eq(42)
      expect(client.rate_limiter.interval_ms).to eq(4200)
    end

    it "takes it from a 429 as readily as from a success" do
      client = build_client
      allow(client.rate_limiter).to receive(:sleep)
      stub_generate_pdf(
        { status: 429, headers: api_headers("x-ratelimit-limit" => "42", "x-ratelimit-interval-ms" => "4200") },
        ok
      )

      generate_pdf(client)

      expect(client.rate_limiter.limit).to eq(42)
    end

    it "keeps what it has when the headers are missing or nonsense" do
      client = build_client
      stub_generate_pdf(status: 200, body: "%PDF", headers: {})

      generate_pdf(client)

      expect(client.rate_limiter.limit).to eq(1000)
    end
  end

  describe "a 429" do
    let(:client) { build_client }

    before { allow(client.rate_limiter).to receive(:sleep) }

    it "is retried after the delay the API asked for, plus the buffer" do
      stub_generate_pdf({ status: 429, headers: api_headers("retry-after" => "0.2") }, ok)

      expect(generate_pdf(client).data).to eq("%PDF")
      expect(client.rate_limiter).to have_received(:sleep).with(0.25).once
    end

    it "waits a second when the API names no delay" do
      stub_generate_pdf({ status: 429, headers: api_headers }, ok)

      generate_pdf(client)

      expect(client.rate_limiter).to have_received(:sleep).with(1.05)
    end

    it "keeps retrying for as long as the API keeps asking, past max_retries" do
      stub_generate_pdf(
        *Array.new(8) { { status: 429, headers: api_headers("retry-after" => "0.1") } },
        ok
      )

      expect(generate_pdf(client).data).to eq("%PDF")
      expect(client.rate_limiter).to have_received(:sleep).exactly(8).times
    end

    it "retries a GraphQL request too" do
      stub_request(:post, "https://app.useanvil.com/graphql").to_return(
        { status: 429, headers: api_headers("retry-after" => "0.1") },
        { status: 200, body: '{"data":{"removeWeldData":true}}', headers: json_headers }
      )

      expect(client.remove_weld_data(eid: "weld123")).to be(true)
      expect(client.rate_limiter).to have_received(:sleep).with(a_value_within(0.001).of(0.15))
    end
  end

  describe "a response the API could not give" do
    let(:client) { build_client }

    before { allow(client).to receive(:sleep) }

    Anvil::Client::RETRY_STATUSES.each do |status|
      it "retries a #{status}" do
        stub_generate_pdf({ status: status, body: "" }, ok)

        expect(generate_pdf(client).data).to eq("%PDF")
      end
    end

    it "does not retry a 4xx, which asking again will not fix" do
      stub_generate_pdf({ status: 400, body: "" }, ok)

      expect { generate_pdf(client) }.to raise_error(Anvil::ValidationError)
      expect(client).not_to have_received(:sleep)
    end

    it "does not retry a 501, which is not in the retry list" do
      stub_generate_pdf({ status: 501, body: "" }, ok)

      expect { generate_pdf(client) }.to raise_error(Anvil::ServerError)
    end

    it "backs off exponentially, doubling each time" do
      stub_generate_pdf({ status: 503, body: "" }, { status: 503, body: "" }, { status: 503, body: "" }, ok)

      generate_pdf(client)

      expect(client).to have_received(:sleep).with(0.1).ordered
      expect(client).to have_received(:sleep).with(0.2).ordered
      expect(client).to have_received(:sleep).with(0.4).ordered
    end

    it "honors a Retry-After on a 503 over the backoff" do
      stub_generate_pdf({ status: 503, body: "", headers: { "retry-after" => "2" } }, ok)

      generate_pdf(client)

      expect(client).to have_received(:sleep).with(2.05)
    end

    it "gives up after max_retries and raises the last error" do
      limited = build_client(max_retries: 2)
      allow(limited).to receive(:sleep)
      stub_generate_pdf({ status: 500, body: "" })

      expect { generate_pdf(limited) }.to raise_error(Anvil::ServerError)
      expect(limited).to have_received(:sleep).twice
    end

    it "does not retry at all when max_retries is zero" do
      never = build_client(max_retries: 0)
      allow(never).to receive(:sleep)
      stub_generate_pdf({ status: 500, body: "" }, ok)

      expect { generate_pdf(never) }.to raise_error(Anvil::ServerError)
      expect(never).not_to have_received(:sleep)
    end

    it "retries a connection that never got there" do
      stub_generate_pdf({ exception: Errno::ECONNRESET }, ok)

      expect(generate_pdf(client).data).to eq("%PDF")
    end

    it "does not retry a timeout, since the request may already have been acted on" do
      stub_request(:post, "https://app.useanvil.com/api/v1/generate-pdf").to_timeout

      expect { generate_pdf(client) }.to raise_error(Anvil::ConnectionError)
      expect(client).not_to have_received(:sleep)
    end
  end
end
