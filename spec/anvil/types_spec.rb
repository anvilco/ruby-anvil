# frozen_string_literal: true

RSpec.describe "Anvil typed payloads and responses" do
  describe Anvil::Payloads::Base do
    it "converts snake_case names to the API's camelCase" do
      payload = Anvil::Payloads::ForgeSubmit.new(forge_eid: "forge123", enforce_payload_valid_on_create: true)

      expect(payload.to_h).to eq({ "forgeEid" => "forge123", "enforcePayloadValidOnCreate" => true })
    end

    it "uses the API's own spelling where no rule would produce it" do
      payload = Anvil::Payloads::CreateEtchPacket.new(webhook_url: "https://x.test", merge_pdfs: true)

      expect(payload.to_h.keys).to contain_exactly("webhookURL", "mergePDFs")
    end

    it "leaves out what was never set, rather than sending null" do
      expect(Anvil::Payloads::FillPdf.new(data: { a: 1 }).to_h).to eq({ "data" => { a: 1 } })
    end

    it "keeps a false, which is a value like any other" do
      expect(Anvil::Payloads::CreateEtchPacket.new(is_test: false).to_h).to eq({ "isTest" => false })
    end

    it "passes through keys it does not know about, camelized" do
      payload = Anvil::Payloads::FillPdf.new(data: {}, some_new_option: "kept")

      expect(payload.to_h["someNewOption"]).to eq("kept")
      expect(payload.extra).to eq({ "someNewOption" => "kept" })
    end

    it "serializes nested payloads and arrays of them" do
      payload = Anvil::Payloads::CreateEtchPacket.new(
        files: [Anvil::Payloads::EtchFile.new(id: "f1", cast_eid: "cast123")]
      )

      expect(payload.to_h).to eq({ "files" => [{ "id" => "f1", "castEid" => "cast123" }] })
    end

    it "round-trips through to_h" do
      payload = Anvil::Payloads::ForgeSubmit.new(forge_eid: "forge123", payload: { a: 1 }, is_test: true)

      expect(Anvil::Payloads::ForgeSubmit.from_h(payload.to_h)).to eq(payload)
    end

    it "returns what it was given when that is already a payload" do
      payload = Anvil::Payloads::FillPdf.new(title: "One")

      expect(Anvil::Payloads::FillPdf.from_h(payload)).to be(payload)
    end

    it "compares by its contents" do
      expect(Anvil::Payloads::FillPdf.new(title: "One")).to eq(Anvil::Payloads::FillPdf.new(title: "One"))
      expect(Anvil::Payloads::FillPdf.new(title: "One")).not_to eq(Anvil::Payloads::FillPdf.new(title: "Two"))
      expect(Anvil::Payloads::FillPdf.new(title: "One")).not_to eq(Anvil::Payloads::GeneratePdf.new(title: "One"))
    end

    it "can be used as a Hash key" do
      hash = { Anvil::Payloads::FillPdf.new(title: "One") => :found }

      expect(hash[Anvil::Payloads::FillPdf.new(title: "One")]).to eq(:found)
    end

    it "shows its payload when inspected" do
      inspected = Anvil::Payloads::FillPdf.new(title: "One").inspect

      expect(inspected).to include("Anvil::Payloads::FillPdf")
      expect(inspected).to include("title")
      expect(inspected).to include("One")
    end

    it "serializes a Time as ISO 8601" do
      payload = Anvil::Payloads::FillPdf.new(data: { signed_at: Time.utc(2026, 11, 17, 10, 0, 0) })

      expect(payload.to_h["data"][:signed_at]).to eq("2026-11-17T10:00:00Z")
    end
  end

  describe Anvil::Types::Base do
    let(:packet) do
      Anvil::Types::EtchPacket.from_h(
        "eid" => "packet123",
        "isTest" => true,
        "detailsURL" => "https://app.useanvil.com/etch/packet123",
        "completedAt" => "2026-11-17T10:00:00.000Z",
        "archivedAt" => nil,
        "documentGroup" => {
          "eid" => "dg123",
          "files" => [{ "name" => "Contract" }],
          "signers" => [
            { "eid" => "signer1", "signActionType" => "sign" },
            { "eid" => "signer2", "signActionType" => "accept" }
          ]
        },
        "aFieldThisClientHasNeverHeardOf" => 42
      )
    end

    it "reads the API's camelCase into snake_case attributes" do
      expect(packet.eid).to eq("packet123")
      expect(packet.is_test).to be(true)
      expect(packet.details_url).to eq("https://app.useanvil.com/etch/packet123")
    end

    it "parses timestamps" do
      expect(packet.completed_at).to eq(Time.utc(2026, 11, 17, 10, 0, 0))
    end

    it "leaves a null timestamp null" do
      expect(packet.archived_at).to be_nil
    end

    it "leaves a timestamp it cannot parse alone" do
      expect(Anvil::Types::EtchPacket.from_h("createdAt" => "whenever").created_at).to eq("whenever")
    end

    it "builds nested objects" do
      expect(packet.document_group).to be_a(Anvil::Types::DocumentGroup)
      expect(packet.document_group.eid).to eq("dg123")
    end

    it "builds arrays of nested objects" do
      expect(packet.document_group.signers.map(&:eid)).to eq(%w[signer1 signer2])
      expect(packet.document_group.signers.first).to be_a(Anvil::Types::Signer)
    end

    it "leaves JSON fields as the plain data they are" do
      expect(packet.document_group.files).to eq([{ "name" => "Contract" }])
    end

    it "reaches the packet's signers through the document group" do
      expect(packet.signers.map(&:sign_action_type)).to eq(%w[sign accept])
    end

    it "has no signers when the response query did not select them" do
      expect(Anvil::Types::EtchPacket.from_h("eid" => "abc").signers).to eq([])
    end

    it "keeps fields this client does not know about" do
      expect(packet["aFieldThisClientHasNeverHeardOf"]).to eq(42)
      expect(packet[:aFieldThisClientHasNeverHeardOf]).to eq(42)
      expect(packet.to_h).to have_key("aFieldThisClientHasNeverHeardOf")
    end

    it "leaves attributes a custom response query did not select as nil" do
      expect(Anvil::Types::EtchPacket.from_h("eid" => "abc").status).to be_nil
    end

    it "is nil when there was nothing to build from" do
      expect(Anvil::Types::EtchPacket.from_h(nil)).to be_nil
    end

    it "returns what it was given when that is already typed" do
      expect(Anvil::Types::EtchPacket.from_h(packet)).to be(packet)
    end

    it "compares by what the API returned" do
      expect(Anvil::Types::Signer.from_h("eid" => "s1")).to eq(Anvil::Types::Signer.from_h("eid" => "s1"))
      expect(Anvil::Types::Signer.from_h("eid" => "s1")).not_to eq(Anvil::Types::Signer.from_h("eid" => "s2"))
    end

    it "can be used as a Hash key" do
      hash = { Anvil::Types::Signer.from_h("eid" => "s1") => :found }

      expect(hash[Anvil::Types::Signer.from_h("eid" => "s1")]).to eq(:found)
    end

    it "shows the fields it has when inspected" do
      inspected = Anvil::Types::Signer.from_h("eid" => "s1").inspect

      expect(inspected).to include("Anvil::Types::Signer")
      expect(inspected).to include('eid="s1"')
      expect(inspected).not_to include("email")
    end
  end

  describe Anvil::GraphQLResponse do
    it "reaches the operation's result by name" do
      response = described_class.new(status_code: 200, body: { "data" => { "etchPacket" => { "eid" => "abc" } } })

      expect(response["etchPacket"]).to eq({ "eid" => "abc" })
      expect(response[:etchPacket]).to eq({ "eid" => "abc" })
    end

    it "has an empty data map when the body carried none" do
      expect(described_class.new(status_code: 200, body: nil).data).to eq({})
    end
  end
end
