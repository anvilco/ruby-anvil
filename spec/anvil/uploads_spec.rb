# frozen_string_literal: true

RSpec.describe "Anvil GraphQL file uploads" do
  let(:client) { build_client }
  let(:upload) { Anvil.prepare_graphql_file(fixture_path("dummy.pdf")) }

  def stub_graphql
    stub_request(:post, "https://app.useanvil.com/graphql")
      .to_return(
        status: 200,
        body: '{"data":{"createEtchPacket":{"eid":"packet123"}}}',
        headers: json_headers
      )
  end

  # The multipart request that was made, split into its parts
  def multipart_request
    request = nil
    expect(WebMock).to(have_requested(:post, "https://app.useanvil.com/graphql").with { |made| request = made })
    boundary = request.headers["Content-Type"][/boundary=(\S+)/, 1]
    [request, request.body.split("--#{boundary}").map(&:strip).reject { |part| part.empty? || part == "--" }]
  end

  describe Anvil::Uploads do
    describe ".extract_files" do
      it "pulls a file out of the variables and records where it was" do
        operation = { query: "mutation {}", variables: { files: [{ id: "f1", file: upload }] } }

        clone, found = described_class.extract_files(operation)

        expect(clone[:variables][:files][0][:file]).to be_nil
        expect(clone[:variables][:files][0][:id]).to eq("f1")
        expect(found.length).to eq(1)
        expect(found[0][0]).to be(upload)
        expect(found[0][1]).to eq(["variables.files.0.file"])
      end

      it "records every path one file was used at, and sends it once" do
        operation = {
          query: "mutation {}",
          variables: { files: [{ file: upload }, { file: upload }] }
        }

        _clone, found = described_class.extract_files(operation)

        expect(found.length).to eq(1)
        expect(found[0][1]).to eq(["variables.files.0.file", "variables.files.1.file"])
      end

      it "leaves an operation with no files alone" do
        operation = { query: "query {}", variables: { eid: "abc", nested: { list: [1, 2] } } }

        clone, found = described_class.extract_files(operation)

        expect(clone).to eq(operation)
        expect(found).to be_empty
      end

      it "wraps a bare IO on the way through" do
        File.open(fixture_path("dummy.pdf"), "rb") do |file|
          operation = { query: "mutation {}", variables: { files: [{ file: file }] } }

          _clone, found = described_class.extract_files(operation)

          expect(found[0][0]).to be_a(Anvil::UploadWithOptions)
          expect(found[0][0].filename).to eq("dummy.pdf")
        end
      end
    end

    describe ".valid_upload_schema?" do
      it "accepts a file under a file key" do
        expect(described_class.valid_upload_schema?({ variables: { files: [{ file: upload }] } })).to be(true)
      end

      it "accepts a base64 upload with its filename and mimetype" do
        schema = {
          variables: {
            files: [{ file: { data: "YWJj", filename: "a.pdf", mimetype: "application/pdf" } }]
          }
        }

        expect(described_class.valid_upload_schema?(schema)).to be(true)
      end

      it "rejects a base64 upload with no filename" do
        schema = { variables: { files: [{ file: { data: "YWJj", mimetype: "application/pdf" } }] } }

        expect(described_class.valid_upload_schema?(schema)).to be(false)
      end

      it "rejects a base64 upload whose data is not a string" do
        schema = { variables: { files: [{ file: { data: 42, filename: "a.pdf", mimetype: "application/pdf" } }] } }

        expect(described_class.valid_upload_schema?(schema)).to be(false)
      end

      it "accepts a URL upload, which the API fetches itself" do
        schema = { variables: { files: [{ file: { url: "https://example.test/a.pdf" } }] } }

        expect(described_class.valid_upload_schema?(schema)).to be(true)
      end

      it "rejects an object under a file key that is no kind of upload" do
        expect(described_class.valid_upload_schema?({ variables: { file: { nope: true } } })).to be(false)
      end

      it "rejects a string under a file key" do
        expect(described_class.valid_upload_schema?({ variables: { file: "i am not a file" } })).to be(false)
      end

      it "rejects a file anywhere other than under a file key" do
        expect(described_class.valid_upload_schema?({ variables: { attachment: upload } })).to be(false)
      end

      it "accepts nil" do
        expect(described_class.valid_upload_schema?(nil)).to be(true)
      end
    end
  end

  describe "a request that carries files" do
    before { stub_graphql }

    it "is sent as multipart/form-data" do
      client.create_etch_packet(variables: { files: [{ id: "f1", file: upload }] })

      request, = multipart_request
      expect(request.headers["Content-Type"]).to start_with("multipart/form-data; boundary=anvil-")
      expect(request.headers["Content-Length"].to_i).to be > 0
    end

    it "sends the operation with the file nulled out" do
      client.create_etch_packet(variables: { files: [{ id: "f1", file: upload }] })

      _request, parts = multipart_request
      operations = parts.find { |part| part.include?('name="operations"') }
      body = JSON.parse(operations.split("\r\n\r\n", 2).last)

      expect(body["variables"]["files"][0]).to eq({ "id" => "f1", "file" => nil })
      expect(body["query"]).to include("mutation CreateEtchPacket(")
    end

    it "sends a map from each part to the variable path it fills" do
      client.create_etch_packet(variables: { files: [{ id: "f1", file: upload }] })

      _request, parts = multipart_request
      map = parts.find { |part| part.include?('name="map"') }

      expect(JSON.parse(map.split("\r\n\r\n", 2).last)).to eq({ "1" => ["variables.files.0.file"] })
    end

    it "sends the file itself, with its filename and content type" do
      client.create_etch_packet(variables: { files: [{ id: "f1", file: upload }] })

      _request, parts = multipart_request
      file_part = parts.find { |part| part.include?('name="1"') }

      expect(file_part).to include('filename="dummy.pdf"')
      expect(file_part).to include("Content-Type: application/pdf")
      expect(file_part).to include("%PDF-1.4")
    end

    it "numbers the parts when there is more than one file" do
      other = Anvil.prepare_graphql_file(StringIO.new("second"), filename: "second.txt")

      client.create_etch_packet(variables: { files: [{ file: upload }, { file: other }] })

      _request, parts = multipart_request
      map = parts.find { |part| part.include?('name="map"') }

      expect(JSON.parse(map.split("\r\n\r\n", 2).last)).to eq(
        "1" => ["variables.files.0.file"],
        "2" => ["variables.files.1.file"]
      )
      expect(parts.find { |part| part.include?('name="2"') }).to include("second")
    end

    it "sends an upload named with a filename of its own under that name" do
      renamed = Anvil.prepare_graphql_file(fixture_path("dummy.pdf"), filename: "contract.pdf")

      client.create_etch_packet(variables: { files: [{ file: renamed }] })

      _request, parts = multipart_request
      expect(parts.find { |part| part.include?('name="1"') }).to include('filename="contract.pdf"')
    end

    it "sends JSON, not multipart, when there are no files" do
      client.create_etch_packet(variables: { name: "No files here" })

      request, = multipart_request
      expect(request.headers["Content-Type"]).to eq("application/json")
    end

    it "refuses to send a file the API would reject" do
      expect { client.request_graphql(query: "mutation {}", variables: { file: "i am not a file" }) }
        .to raise_error(Anvil::ConfigurationError, /Invalid File schema detected/)
    end
  end

  describe Anvil::Multipart do
    it "escapes a filename that would otherwise break the headers" do
      upload = Anvil.prepare_graphql_file(StringIO.new("x"), filename: %(we"ird\r\nname.pdf))

      body = described_class.build(operations: "{}", map: "{}", uploads: [upload])
      content = body.io.read
      body.close

      expect(content).to include('filename="we%22irdname.pdf"')
      expect(content.lines.grep(/Content-Disposition/).length).to eq(3)
    end

    it "refuses an upload with no filename at all" do
      upload = Anvil.prepare_graphql_file(StringIO.new("x"), ignore_filename_validation: true)

      expect { described_class.build(operations: "{}", map: "{}", uploads: [upload]) }
        .to raise_error(Anvil::ConfigurationError, /missing a filename/)
    end
  end
end
