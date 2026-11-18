# frozen_string_literal: true

RSpec.describe Anvil::Client do
  describe "authentication" do
    it "sends the Authorization header on a REST request" do
      client = build_client
      stub = stub_request(:post, "https://app.useanvil.com/api/v1/generate-pdf")
        .with(headers: { "Authorization" => "Basic YWJjMTIzOg==" })
        .to_return(status: 200, body: "%PDF", headers: api_headers)

      client.generate_pdf(type: "html", data: { html: "<p>hi</p>" })

      expect(stub).to have_been_requested
    end

    it "sends the Authorization header on a GraphQL request" do
      client = build_client(access_token: "def345", api_key: nil)
      stub = stub_request(:post, "https://app.useanvil.com/graphql")
        .with(headers: { "Authorization" => "Bearer ZGVmMzQ1" })
        .to_return(status: 200, body: '{"data":{"etchPacket":{"eid":"abc"}}}', headers: json_headers)

      client.get_etch_packet(eid: "abc")

      expect(stub).to have_been_requested
    end

    it "falls back to the ANVIL_API_KEY environment variable" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ANVIL_API_KEY", nil).and_return("from-the-env")

      expect(described_class.new.auth_header).to eq("Basic #{["from-the-env:"].pack("m0")}")
    end

    it "prefers an API key passed in over the environment" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ANVIL_API_KEY", nil).and_return("from-the-env")

      expect(described_class.new(api_key: "passed-in").auth_header).to eq("Basic #{["passed-in:"].pack("m0")}")
    end

    it "requires an API key or an access token" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ANVIL_API_KEY", nil).and_return(nil)

      expect { described_class.new }
        .to raise_error(Anvil::ConfigurationError, /api_key or an access_token is required/)
    end
  end

  describe "base_url" do
    it "defaults to production" do
      expect(build_client.base_url).to eq("https://app.useanvil.com")
    end

    it "takes a configured environment" do
      client = build_client(base_url: "https://staging.useanvil.com")

      expect(client.base_url).to eq("https://staging.useanvil.com")
    end

    it "drops a trailing slash so paths do not double up" do
      expect(build_client(base_url: "https://staging.useanvil.com/").base_url).to eq("https://staging.useanvil.com")
    end

    it "refuses a base_url that is not an http(s) URL" do
      expect { described_class.new(api_key: "abc123", base_url: "app.useanvil.com") }
        .to raise_error(Anvil::ConfigurationError, /must be an http\(s\) URL/)
    end

    context "when it is configured" do
      let(:client) { build_client(base_url: "https://staging.useanvil.com") }

      it "derives the REST endpoints from it" do
        stub = stub_request(:post, "https://staging.useanvil.com/api/v1/fill/abc.pdf")
          .to_return(status: 200, body: "%PDF", headers: api_headers)

        client.fill_pdf("abc", data: {})

        expect(stub).to have_been_requested
      end

      it "derives the GraphQL endpoint from it, not graphql.useanvil.com" do
        stub = stub_request(:post, "https://staging.useanvil.com/graphql")
          .to_return(status: 200, body: '{"data":{"removeWeldData":true}}', headers: json_headers)

        client.remove_weld_data(eid: "abc")

        expect(stub).to have_been_requested
      end

      it "derives the document download URL from it" do
        stub = stub_request(:get, "https://staging.useanvil.com/api/document-group/dg123.zip")
          .to_return(status: 200, body: "PK", headers: api_headers)

        client.download_documents("dg123")

        expect(stub).to have_been_requested
      end
    end
  end

  describe "the User-Agent" do
    it "names the repo and the gem's version, as the SDK conventions require" do
      expect(build_client.user_agent).to eq("ruby-anvil/#{Anvil::VERSION}")
    end

    it "can be overridden" do
      client = build_client(user_agent: "My App/1.0")
      stub = stub_request(:get, "https://app.useanvil.com/api/document-group/dg.zip")
        .with(headers: { "User-Agent" => "My App/1.0" })
        .to_return(status: 200, body: "PK", headers: api_headers)

      client.download_documents("dg")

      expect(stub).to have_been_requested
    end
  end

  describe "#request_rest" do
    let(:client) { build_client }

    it "sends a Hash body as JSON" do
      stub = stub_request(:post, "https://app.useanvil.com/api/v1/anything")
        .with(body: '{"a":1}', headers: { "Content-Type" => "application/json" })
        .to_return(status: 200, body: "ok", headers: api_headers)

      client.request_rest("/api/v1/anything", method: :post, body: { a: 1 })

      expect(stub).to have_been_requested
    end

    it "sends a String body untouched" do
      stub = stub_request(:post, "https://app.useanvil.com/api/v1/anything")
        .with(body: "raw")
        .to_return(status: 200, body: "ok", headers: api_headers)

      client.request_rest("/api/v1/anything", method: :post, body: "raw")

      expect(stub).to have_been_requested
    end

    it "takes a whole URL as well as a path" do
      stub = stub_request(:get, "https://staging.useanvil.com/api/v1/anything")
        .to_return(status: 200, body: "ok", headers: api_headers)

      client.request_rest("https://staging.useanvil.com/api/v1/anything")

      expect(stub).to have_been_requested
    end

    it "returns the status code and headers alongside the data" do
      stub_request(:get, "https://app.useanvil.com/api/v1/anything")
        .to_return(status: 200, body: "ok", headers: api_headers("content-length" => "2"))

      response = client.request_rest("/api/v1/anything")

      expect(response).to be_a(Anvil::RestResponse)
      expect(response.status_code).to eq(200)
      expect(response).to be_success
      expect(response.content_length).to eq(2)
      expect(response.data).to eq("ok")
    end

    it "reports the response's content type" do
      stub_request(:get, "https://app.useanvil.com/api/v1/anything")
        .to_return(status: 200, body: "%PDF", headers: api_headers("content-type" => "application/pdf"))

      expect(client.request_rest("/api/v1/anything").content_type).to eq("application/pdf")
    end

    it "streams a JSON body too, once it has been checked for errors" do
      stub_request(:get, "https://app.useanvil.com/api/v1/anything")
        .to_return(status: 200, body: '{"ok":true}', headers: json_headers)
      chunks = []

      client.request_rest("/api/v1/anything", data_type: :stream) { |chunk| chunks << chunk }

      expect(JSON.parse(chunks.join)).to eq({ "ok" => true })
    end

    it "refuses a URL it cannot parse" do
      expect { client.request_rest("/api/v1/a path with spaces") }
        .to raise_error(Anvil::ConfigurationError, /Invalid URL/)
    end

    it "refuses an unsupported HTTP method" do
      expect { client.request_rest("/x", method: :options) }
        .to raise_error(Anvil::ConfigurationError, /Unsupported HTTP method/)
    end

    it "refuses an unsupported data_type" do
      expect { client.request_rest("/x", data_type: :buffer) }
        .to raise_error(Anvil::ConfigurationError, /data_type must be one of/)
    end

    describe "response types" do
      before do
        stub_request(:get, "https://app.useanvil.com/api/v1/anything")
          .to_return(status: 200, body: "the bytes", headers: api_headers)
      end

      it "returns a String by default" do
        expect(client.request_rest("/api/v1/anything").data).to eq("the bytes")
      end

      it "returns a StringIO for :io" do
        data = client.request_rest("/api/v1/anything", data_type: :io).data

        expect(data).to be_a(StringIO)
        expect(data.read).to eq("the bytes")
      end

      it "hands each chunk to a block for :stream, and returns the bytes written" do
        chunks = []

        response = client.request_rest("/api/v1/anything", data_type: :stream) { |chunk| chunks << chunk }

        expect(chunks.join).to eq("the bytes")
        expect(response.data).to eq(9)
      end

      it "writes to a given IO for :stream" do
        sink = StringIO.new

        client.request_rest("/api/v1/anything", data_type: :stream, to: sink)

        expect(sink.string).to eq("the bytes")
      end

      it "refuses :stream with nowhere to stream to" do
        expect { client.request_rest("/api/v1/anything", data_type: :stream) }
          .to raise_error(Anvil::ConfigurationError, /needs a block or a `to:` IO/)
      end
    end

    it "parses a JSON response for :json" do
      stub_request(:get, "https://app.useanvil.com/api/v1/anything")
        .to_return(status: 200, body: '{"ok":true}', headers: json_headers)

      expect(client.request_rest("/api/v1/anything", data_type: :json).data).to eq({ "ok" => true })
    end

    it "raises when the API answers with JSON this client cannot parse" do
      stub_request(:get, "https://app.useanvil.com/api/v1/anything")
        .to_return(status: 200, body: "{not json", headers: json_headers)

      expect { client.request_rest("/api/v1/anything") }
        .to raise_error(Anvil::ConnectionError, /Could not parse the API's JSON response/)
    end

    it "raises when the API cannot be reached" do
      stub_request(:get, "https://app.useanvil.com/api/v1/anything").to_timeout

      expect { client.request_rest("/api/v1/anything") }
        .to raise_error(Anvil::ConnectionError, /Could not reach/)
    end
  end
end
