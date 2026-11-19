# frozen_string_literal: true

RSpec.describe Anvil::Auth do
  # A JWT whose header and payload are real JSON objects
  def jwt(header: { alg: "HS256", typ: "JWT" }, payload: { sub: "user" }, signature: "sig")
    segments = [header, payload].map { |part| [JSON.generate(part)].pack("m0").tr("+/", "-_").delete("=") }
    "#{segments.join(".")}.#{signature}"
  end

  describe ".build_header" do
    it "sends an API key as Basic, base64 of the key and a trailing colon" do
      expect(described_class.build_header(api_key: "abc123")).to eq("Basic YWJjMTIzOg==")
    end

    it "sends a JWT access token verbatim, which is what the API wants" do
      token = jwt

      expect(described_class.build_header(access_token: token)).to eq("Bearer #{token}")
    end

    it "base64 encodes any other access token, which the API still accepts" do
      expect(described_class.build_header(access_token: "def345")).to eq("Bearer ZGVmMzQ1")
    end

    it "prefers the access token when both are given" do
      expect(described_class.build_header(api_key: "abc123", access_token: "def345")).to start_with("Bearer ")
    end

    it "treats an empty credential as missing" do
      expect(described_class.build_header(api_key: "abc123", access_token: "")).to start_with("Basic ")
    end

    [{}, { api_key: nil }, { api_key: "" }, { access_token: "" }, { api_key: "", access_token: "" }]
      .each do |credentials|
      it "refuses to build a header out of #{credentials.inspect}" do
        expect { described_class.build_header(**credentials) }
          .to raise_error(Anvil::ConfigurationError, /api_key or an access_token is required/)
      end
    end

    it "does not wrap the base64 across lines, however long the key" do
      expect(described_class.build_header(api_key: "k" * 500)).not_to include("\n")
    end
  end

  describe ".jwt?" do
    it "accepts three base64url segments whose header and payload are JSON objects" do
      expect(described_class.jwt?(jwt)).to be(true)
    end

    it "accepts an empty signature" do
      expect(described_class.jwt?(jwt(signature: ""))).to be(true)
    end

    it "rejects a token with the wrong number of segments" do
      expect(described_class.jwt?("header.payload")).to be(false)
      expect(described_class.jwt?("a.b.c.d")).to be(false)
    end

    it "rejects a header with no string alg" do
      expect(described_class.jwt?(jwt(header: { typ: "JWT" }))).to be(false)
      expect(described_class.jwt?(jwt(header: { alg: 256 }))).to be(false)
    end

    it "rejects segments that are not JSON objects" do
      expect(described_class.jwt?(jwt(payload: "a string"))).to be(false)
    end

    it "rejects segments that are not base64 at all" do
      expect(described_class.jwt?("not!base64.at!all.nope")).to be(false)
    end

    it "rejects anything that is not a string" do
      expect(described_class.jwt?(nil)).to be(false)
      expect(described_class.jwt?(42)).to be(false)
    end
  end
end
