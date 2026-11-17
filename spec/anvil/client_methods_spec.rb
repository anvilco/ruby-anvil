# frozen_string_literal: true

RSpec.describe "Anvil::Client API methods" do
  let(:client) { build_client }

  # The body of the one GraphQL request that was made, parsed
  def graphql_request
    body = nil
    expect(WebMock).to(have_requested(:post, "https://app.useanvil.com/graphql")
      .with { |request| body = JSON.parse(request.body) })
    body
  end

  def stub_graphql(data)
    stub_request(:post, "https://app.useanvil.com/graphql")
      .to_return(status: 200, body: JSON.generate({ data: data }), headers: json_headers)
  end

  describe "#fill_pdf" do
    it "posts the payload to the template's fill endpoint and returns the PDF" do
      stub_request(:post, "https://app.useanvil.com/api/v1/fill/kA6Da9CuGqUtc6QiBDRR.pdf")
        .with(
          body: '{"title":"My PDF","data":{"someFieldId":"Hello World!"}}',
          headers: { "Content-Type" => "application/json" }
        )
        .to_return(status: 200, body: "%PDF-1.4 filled", headers: api_headers)

      response = client.fill_pdf("kA6Da9CuGqUtc6QiBDRR", title: "My PDF", data: { someFieldId: "Hello World!" })

      expect(response.status_code).to eq(200)
      expect(response.data).to eq("%PDF-1.4 filled")
    end

    it "takes a typed payload" do
      stub = stub_request(:post, "https://app.useanvil.com/api/v1/fill/abc.pdf")
        .with(body: '{"title":"My PDF","fontSize":10,"textColor":"#CC0000","data":{"name":"Sally"}}')
        .to_return(status: 200, body: "%PDF", headers: api_headers)

      client.fill_pdf(
        "abc",
        Anvil::Payloads::FillPdf.new(title: "My PDF", font_size: 10, text_color: "#CC0000", data: { name: "Sally" })
      )

      expect(stub).to have_been_requested
    end

    it "asks for a version when one is given" do
      stub = stub_request(:post, "https://app.useanvil.com/api/v1/fill/abc.pdf?versionNumber=7")
        .to_return(status: 200, body: "%PDF", headers: api_headers)

      client.fill_pdf("abc", { data: {} }, version_number: 7)

      expect(stub).to have_been_requested
    end

    it "asks for the latest version with VERSION_LATEST" do
      stub = stub_request(:post, "https://app.useanvil.com/api/v1/fill/abc.pdf?versionNumber=-1")
        .to_return(status: 200, body: "%PDF", headers: api_headers)

      client.fill_pdf("abc", { data: {} }, version_number: Anvil::VERSION_LATEST)

      expect(stub).to have_been_requested
    end

    it "streams the PDF to a block when asked to" do
      stub_request(:post, "https://app.useanvil.com/api/v1/fill/abc.pdf")
        .to_return(status: 200, body: "%PDF streamed", headers: api_headers)
      chunks = []

      client.fill_pdf("abc", { data: {} }, data_type: :stream) { |chunk| chunks << chunk }

      expect(chunks.join).to eq("%PDF streamed")
    end

    it "requires a template id" do
      expect { client.fill_pdf("", data: {}) }
        .to raise_error(Anvil::ConfigurationError, /pdf_template_id is required/)
    end

    it "refuses a data_type that cannot hold a PDF" do
      expect { client.fill_pdf("abc", { data: {} }, data_type: :json) }
        .to raise_error(Anvil::ConfigurationError, /data_type must be one of :string, :io, :stream/)
    end
  end

  describe "#generate_pdf" do
    it "posts the payload to the generate endpoint and returns the PDF" do
      stub_request(:post, "https://app.useanvil.com/api/v1/generate-pdf")
        .with(body: '{"title":"Example","type":"html","data":{"html":"<h1>Hi</h1>"}}')
        .to_return(status: 200, body: "%PDF-1.4 generated", headers: api_headers)

      response = client.generate_pdf(title: "Example", type: "html", data: { html: "<h1>Hi</h1>" })

      expect(response.data).to eq("%PDF-1.4 generated")
    end

    it "takes a typed payload" do
      stub = stub_request(:post, "https://app.useanvil.com/api/v1/generate-pdf")
        .with(body: '{"title":"Invoice","type":"markdown","data":[{"label":"Name","content":"Sally"}]}')
        .to_return(status: 200, body: "%PDF", headers: api_headers)

      client.generate_pdf(
        Anvil::Payloads::GeneratePdf.new(
          title: "Invoice",
          type: "markdown",
          data: [{ label: "Name", content: "Sally" }]
        )
      )

      expect(stub).to have_been_requested
    end
  end

  describe "#download_documents" do
    it "gets the document group's zip" do
      stub_request(:get, "https://app.useanvil.com/api/document-group/dg123.zip")
        .to_return(status: 200, body: "PKzip", headers: api_headers)

      response = client.download_documents("dg123")

      expect(response.data).to start_with("PK")
    end

    it "writes the zip to a given IO when streaming" do
      stub_request(:get, "https://app.useanvil.com/api/document-group/dg123.zip")
        .to_return(status: 200, body: "PKzipbytes", headers: api_headers)
      sink = StringIO.new

      response = client.download_documents("dg123", data_type: :stream, to: sink)

      expect(sink.string).to eq("PKzipbytes")
      expect(response.data).to eq(10)
    end

    it "requires a document group eid" do
      expect { client.download_documents(nil) }
        .to raise_error(Anvil::ConfigurationError, /document_group_eid is required/)
    end
  end

  describe "#create_etch_packet" do
    let(:packet) do
      {
        "eid" => "packet123",
        "name" => "Test Docs",
        "status" => "sent",
        "isTest" => true,
        "detailsURL" => "https://app.useanvil.com/org/x/etch/packet123",
        "createdAt" => "2026-11-17T10:00:00.000Z",
        "documentGroup" => {
          "eid" => "dg123",
          "status" => "sent",
          "files" => [{ "name" => "Contract" }],
          "signers" => [{ "eid" => "signer123", "aliasId" => "signer1", "status" => "sent" }]
        }
      }
    end

    it "sends the CreateEtchPacket mutation with the given variables" do
      stub_graphql("createEtchPacket" => packet)

      client.create_etch_packet(variables: { name: "Test Docs", isTest: true })

      expect(graphql_request["query"]).to include("mutation CreateEtchPacket(")
      expect(graphql_request["query"]).to include("createCastTemplatesFromUploads: $createCastTemplatesFromUploads")
      expect(graphql_request["variables"]).to eq({ "name" => "Test Docs", "isTest" => true })
    end

    it "selects the default response fields" do
      stub_graphql("createEtchPacket" => packet)

      client.create_etch_packet(variables: {})

      expect(graphql_request["query"]).to include("numberRemainingSigners")
      expect(graphql_request["query"]).to include("signActionType")
    end

    it "returns a typed packet" do
      stub_graphql("createEtchPacket" => packet)

      result = client.create_etch_packet(variables: {})

      expect(result).to be_a(Anvil::Types::EtchPacket)
      expect(result.eid).to eq("packet123")
      expect(result.details_url).to eq("https://app.useanvil.com/org/x/etch/packet123")
      expect(result.created_at).to eq(Time.utc(2026, 11, 17, 10, 0, 0))
      expect(result.document_group.eid).to eq("dg123")
      expect(result.signers.map(&:alias_id)).to eq(["signer1"])
    end

    it "converts a typed payload to the API's variable names" do
      stub_graphql("createEtchPacket" => packet)

      client.create_etch_packet(
        variables: Anvil::Payloads::CreateEtchPacket.new(
          name: "Test Docs",
          is_test: true,
          merge_pdfs: true,
          webhook_url: "https://example.test/hook",
          files: [Anvil::Payloads::EtchFile.new(id: "f1", cast_eid: "cast123")],
          signers: [
            Anvil::Payloads::EtchSigner.new(
              id: "signer1",
              name: "Sally",
              email: "sally@example.test",
              signer_type: "embedded",
              fields: [Anvil::Payloads::SignerField.new(file_id: "f1", field_id: "signature")]
            )
          ]
        )
      )

      expect(graphql_request["variables"]).to eq(
        "name" => "Test Docs",
        "isTest" => true,
        "mergePDFs" => true,
        "webhookURL" => "https://example.test/hook",
        "files" => [{ "id" => "f1", "castEid" => "cast123" }],
        "signers" => [{
          "id" => "signer1",
          "name" => "Sally",
          "email" => "sally@example.test",
          "signerType" => "embedded",
          "fields" => [{ "fileId" => "f1", "fieldId" => "signature" }]
        }]
      )
    end

    it "takes a custom response query" do
      stub_graphql("createEtchPacket" => { "eid" => "packet123" })

      client.create_etch_packet(variables: {}, response_query: "{ eid }")

      expect(graphql_request["query"]).to include(") { eid }")
      expect(graphql_request["query"]).not_to include("numberRemainingSigners")
    end

    it "takes a mutation of your own" do
      stub_graphql("createEtchPacket" => { "eid" => "packet123" })

      client.create_etch_packet(variables: {}, mutation: "mutation Mine { createEtchPacket { eid } }")

      expect(graphql_request["query"]).to eq("mutation Mine { createEtchPacket { eid } }")
    end
  end

  describe "#get_etch_packet" do
    before { stub_graphql("etchPacket" => { "eid" => "packet123", "status" => "completed" }) }

    it "sends the EtchPacket query for the eid" do
      client.get_etch_packet(eid: "packet123")

      expect(graphql_request["query"]).to include("query EtchPacket (")
      expect(graphql_request["variables"]).to eq({ "eid" => "packet123" })
    end

    it "takes the variables whole instead" do
      client.get_etch_packet(variables: { eid: "packet123" })

      expect(graphql_request["variables"]).to eq({ "eid" => "packet123" })
    end

    it "returns a typed packet" do
      expect(client.get_etch_packet(eid: "packet123").status).to eq("completed")
    end

    it "takes a custom response query" do
      client.get_etch_packet(eid: "packet123", response_query: "{ eid status }")

      expect(graphql_request["query"]).to include(") { eid status }")
    end
  end

  describe "#generate_etch_sign_url" do
    it "sends the GenerateEtchSignURL mutation and returns the URL" do
      stub_graphql("generateEtchSignURL" => "https://app.useanvil.com/etch/sign/abc")

      url = client.generate_etch_sign_url(signer_eid: "signer123", client_user_id: "user42")

      expect(url).to eq("https://app.useanvil.com/etch/sign/abc")
      expect(graphql_request["query"]).to include("mutation GenerateEtchSignURL (")
      expect(graphql_request["variables"]).to eq({ "signerEid" => "signer123", "clientUserId" => "user42" })
    end
  end

  describe "#forge_submit" do
    let(:submission) do
      {
        "eid" => "sub123",
        "status" => "in-progress",
        "continueURL" => "https://app.useanvil.com/w/continue",
        "weldData" => { "eid" => "weld123", "isComplete" => false, "isTest" => true },
        "signer" => { "name" => "Sally", "email" => "sally@example.test" }
      }
    end

    it "sends the ForgeSubmit mutation with the given variables" do
      stub_graphql("forgeSubmit" => submission)

      client.forge_submit(variables: { forgeEid: "forge123", payload: { name: "Sally" } })

      expect(graphql_request["query"]).to include("mutation ForgeSubmit(")
      expect(graphql_request["query"]).to include("$forgeEid: String!")
      expect(graphql_request["variables"]).to eq(
        { "forgeEid" => "forge123", "payload" => { "name" => "Sally" } }
      )
    end

    it "returns a typed submission" do
      stub_graphql("forgeSubmit" => submission)

      result = client.forge_submit(variables: { forgeEid: "forge123", payload: {} })

      expect(result).to be_a(Anvil::Types::ForgeSubmission)
      expect(result.eid).to eq("sub123")
      expect(result.continue_url).to eq("https://app.useanvil.com/w/continue")
      expect(result.weld_data.eid).to eq("weld123")
      expect(result.weld_data.is_complete).to be(false)
      expect(result.signer.name).to eq("Sally")
    end

    it "converts a typed payload to the API's variable names" do
      stub_graphql("forgeSubmit" => submission)

      client.forge_submit(
        variables: Anvil::Payloads::ForgeSubmit.new(
          forge_eid: "forge123",
          weld_data_eid: "weld123",
          payload: { name: "Sally" },
          is_test: true,
          webhook_url: "https://example.test/hook"
        )
      )

      expect(graphql_request["variables"]).to eq(
        "forgeEid" => "forge123",
        "weldDataEid" => "weld123",
        "payload" => { "name" => "Sally" },
        "isTest" => true,
        "webhookURL" => "https://example.test/hook"
      )
    end
  end

  describe "#remove_weld_data" do
    it "sends the RemoveWeldData mutation and returns whether it worked" do
      stub_graphql("removeWeldData" => true)

      expect(client.remove_weld_data(eid: "weld123")).to be(true)
      expect(graphql_request["query"]).to include("mutation RemoveWeldData (")
      expect(graphql_request["variables"]).to eq({ "eid" => "weld123" })
    end

    it "returns false when the API says it did not" do
      stub_graphql("removeWeldData" => false)

      expect(client.remove_weld_data(eid: "weld123")).to be(false)
    end
  end

  describe "#request_graphql" do
    it "posts the query and variables, and returns the data" do
      stub_graphql("weldData" => { "eid" => "weld123", "isComplete" => true })

      response = client.request_graphql(
        query: "query WeldData($eid: String!) { weldData(eid: $eid) { eid isComplete } }",
        variables: { eid: "weld123" }
      )

      expect(response).to be_a(Anvil::GraphQLResponse)
      expect(response.status_code).to eq(200)
      expect(response["weldData"]).to eq({ "eid" => "weld123", "isComplete" => true })
      expect(response.data.keys).to eq(["weldData"])
      expect(response.body).to have_key("data")
    end

    it "defaults the variables to an empty object" do
      stub_graphql("currentUser" => { "eid" => "user123" })

      client.request_graphql(query: "{ currentUser { eid } }")

      expect(graphql_request["variables"]).to eq({})
    end
  end
end
