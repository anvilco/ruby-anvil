# frozen_string_literal: true

RSpec.describe "Anvil error handling" do
  let(:client) { build_client }

  describe Anvil::Errors do
    describe ".looks_like_json_error?" do
      it "sees a GraphQL errors array" do
        expect(described_class.looks_like_json_error?({ "errors" => [] })).to be(true)
      end

      it "sees a bare message" do
        expect(described_class.looks_like_json_error?({ "message" => "Nope" })).to be(true)
      end

      it "sees a bare name" do
        expect(described_class.looks_like_json_error?({ "name" => "ValidationError" })).to be(true)
      end

      it "does not see an ordinary response" do
        expect(described_class.looks_like_json_error?({ "data" => { "eid" => "abc" } })).to be(false)
      end

      it "does not see a non-Hash body" do
        expect(described_class.looks_like_json_error?("a string")).to be(false)
        expect(described_class.looks_like_json_error?(nil)).to be(false)
      end
    end

    describe ".normalize" do
      it "normalizes GraphQL errors" do
        errors = described_class.normalize(
          { "errors" => [{ "message" => "Cannot query field", "path" => %w[organization nope] }] }
        )

        expect(errors.length).to eq(1)
        expect(errors.first.message).to eq("Cannot query field")
        expect(errors.first.path).to eq(%w[organization nope])
      end

      it "normalizes a REST error with a name and a message" do
        errors = described_class.normalize(
          { "name" => "AssertionError", "message" => "PDF did not generate properly from given HTML!" }
        )

        expect(errors.first.name).to eq("AssertionError")
        expect(errors.first.to_s).to eq("AssertionError: PDF did not generate properly from given HTML!")
      end

      it "normalizes a REST validation error's fields" do
        errors = described_class.normalize(
          {
            "name" => "ValidationError",
            "fields" => [{ "message" => "Required", "property" => "data" }]
          }
        )

        expect(errors.first.fields.length).to eq(1)
        expect(errors.first.fields.first.property).to eq("data")
        expect(errors.first.fields.first.message).to eq("Required")
        expect(errors.first.to_s).to eq("ValidationError (data: Required)")
      end

      it "falls back to the HTTP reason phrase when the body says nothing" do
        errors = described_class.normalize(nil, status_text: "Not Found")

        expect(errors.first.name).to eq("Not Found")
        expect(errors.first.message).to eq("Not Found")
      end

      it "keeps anything it does not understand in raw" do
        errors = described_class.normalize({ "errors" => [{ "message" => "Nope", "extensions" => { "code" => 42 } }] })

        expect(errors.first.raw["extensions"]).to eq({ "code" => 42 })
      end

      it "normalizes an error that is a bare string" do
        errors = described_class.normalize({ "errors" => ["just a string"] })

        expect(errors.first.message).to eq("just a string")
      end
    end

    describe ".error_class_for" do
      {
        400 => Anvil::ValidationError,
        401 => Anvil::AuthenticationError,
        403 => Anvil::ForbiddenError,
        404 => Anvil::NotFoundError,
        422 => Anvil::ValidationError,
        429 => Anvil::RateLimitError,
        418 => Anvil::ClientError,
        500 => Anvil::ServerError,
        503 => Anvil::ServerError
      }.each do |status, klass|
        it "maps #{status} to #{klass}" do
          expect(described_class.error_class_for(status)).to eq(klass)
        end
      end

      it "falls back to ResponseError for anything else" do
        expect(described_class.error_class_for(nil)).to eq(Anvil::ResponseError)
      end
    end
  end

  describe "raised from a REST call" do
    it "raises AuthenticationError on a 401" do
      stub_request(:post, "https://app.useanvil.com/api/v1/generate-pdf")
        .to_return(
          status: 401,
          body: '{"name":"AuthenticationError","message":"Invalid API key"}',
          headers: json_headers
        )

      expect { client.generate_pdf(type: "html", data: {}) }
        .to raise_error(Anvil::AuthenticationError, /Invalid API key/) do |error|
          expect(error.status_code).to eq(401)
          expect(error.error.name).to eq("AuthenticationError")
          expect(error).to be_a(Anvil::ResponseError)
          expect(error).to be_a(Anvil::Error)
        end
    end

    it "raises ValidationError with the field-level details on a 422" do
      stub_request(:post, "https://app.useanvil.com/api/v1/fill/abc.pdf")
        .to_return(
          status: 422,
          body: '{"name":"ValidationError","fields":[{"message":"Required","property":"data"}]}',
          headers: json_headers
        )

      expect { client.fill_pdf("abc", data: {}) }
        .to raise_error(Anvil::ValidationError) do |error|
          expect(error.status_code).to eq(422)
          expect(error.fields.map(&:property)).to eq(["data"])
          expect(error.fields.map(&:message)).to eq(["Required"])
          expect(error.message).to eq("ValidationError (data: Required)")
        end
    end

    it "raises NotFoundError on a 404" do
      stub_request(:get, "https://app.useanvil.com/api/document-group/nope.zip")
        .to_return(status: 404, body: "Not Found", headers: api_headers)

      expect { client.download_documents("nope") }
        .to raise_error(Anvil::NotFoundError) do |error|
          expect(error.status_code).to eq(404)
          expect(error.body).to eq("Not Found")
        end
    end

    it "raises ServerError on a 500" do
      stub_request(:post, "https://app.useanvil.com/api/v1/generate-pdf")
        .to_return(status: 500, body: "", headers: api_headers)

      expect { client.generate_pdf(type: "html", data: {}) }
        .to raise_error(Anvil::ServerError)
    end

    # node-anvil counts this as an error; python-anvil and dotnet-anvil do not,
    # and the SDK conventions call node's the legacy divergence
    it "does not raise on a 2xx body carrying only a name and a message" do
      stub_request(:post, "https://app.useanvil.com/api/v1/generate-pdf")
        .to_return(
          status: 200,
          body: '{"name":"AssertionError","message":"PDF did not generate properly from given HTML!"}',
          headers: json_headers
        )

      response = client.generate_pdf(type: "html", data: {})

      expect(response.status_code).to eq(200)
      expect(JSON.parse(response.data)["name"]).to eq("AssertionError")
    end

    it "still raises when a 2xx carries a GraphQL errors array" do
      stub_request(:post, "https://app.useanvil.com/api/v1/generate-pdf")
        .to_return(status: 200, body: '{"errors":[{"message":"Nope"}]}', headers: json_headers)

      expect { client.generate_pdf(type: "html", data: {}) }.to raise_error(Anvil::GraphQLError, /Nope/)
    end
  end

  describe "raised from a GraphQL call" do
    it "raises GraphQLError on a 200 that carries errors" do
      stub_request(:post, "https://app.useanvil.com/graphql")
        .to_return(
          status: 200,
          body: JSON.generate(
            errors: [
              { message: "Cannot query field \"nope\" on type \"User\"." },
              { message: "Variable $eid is required." }
            ]
          ),
          headers: json_headers
        )

      expect { client.get_etch_packet(eid: "abc") }
        .to raise_error(Anvil::GraphQLError) do |error|
          expect(error.status_code).to eq(200)
          expect(error.errors.length).to eq(2)
          expect(error.message).to include("Cannot query field")
          expect(error.message).to include("Variable $eid is required.")
        end
    end

    it "raises the status-based error when GraphQL fails with a non-200" do
      stub_request(:post, "https://app.useanvil.com/graphql")
        .to_return(status: 401, body: '{"errors":[{"message":"Unauthorized"}]}', headers: json_headers)

      expect { client.get_etch_packet(eid: "abc") }
        .to raise_error(Anvil::AuthenticationError, /Unauthorized/)
    end
  end

  describe Anvil::ErrorDetail do
    it "describes itself with whatever it has" do
      expect(described_class.new(message: "Nope").to_s).to eq("Nope")
      expect(described_class.new(name: "Nope").to_s).to eq("Nope")
      expect(described_class.new(name: "Same", message: "Same").to_s).to eq("Same")
      expect(described_class.new.to_s).to eq("Unknown Error")
    end

    it "keeps a field error as the API sent it" do
      field = Anvil::ErrorField.from_h({ "message" => "Required", "property" => "data", "code" => 7 })

      expect(field.to_h).to eq({ "message" => "Required", "property" => "data", "code" => 7 })
      expect(field.to_s).to eq("data: Required")
    end

    it "takes a field error that is a bare string" do
      expect(Anvil::ErrorField.from_h("Required").to_s).to eq("Required")
    end

    it "keeps the error it was built from" do
      detail = described_class.from_h({ "message" => "Nope", "other" => 1 })

      expect(detail.to_h).to eq({ "message" => "Nope", "other" => 1 })
    end
  end
end
