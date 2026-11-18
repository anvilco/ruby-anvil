# frozen_string_literal: true

require "json"

RSpec.describe "the generated types" do
  let(:pinned_version) do
    package = JSON.parse(File.read(File.expand_path("../../dev/package.json", __dir__)))
    package["dependencies"]["@anvilco/types"]
  end
  let(:generated_dir) { File.expand_path("../../lib/anvil/types/generated", __dir__) }

  it "comes from the @anvilco/types version dev/package.json pins" do
    Dir[File.join(generated_dir, "*.rb")].each do |file|
      expect(File.readlines(file)[2]).to include("@anvilco/types@#{pinned_version}"), file
    end
  end

  it "has one Args class per query and mutation in the schema" do
    args = Anvil::Operations.constants.grep(/Args\z/)

    expect(args.size).to eq(Anvil::Operations::NAMES.values.sum(&:size))
    expect(args).to include(:CreateEtchPacketArgs, :EtchPacketArgs, :GenerateEtchSignUrlArgs, :CurrentUserArgs)
  end

  it "has an Args class for every operation the client sends" do
    %w[createEtchPacket etchPacket generateEtchSignURL forgeSubmit removeWeldData currentUser].each do |name|
      expect(Anvil::Operations::NAMES.values.flatten).to include(name)
    end
  end

  it "builds nested response objects from a GraphQL response" do
    packet = Anvil::Types::EtchPacket.from_h(
      "eid" => "p1", "detailsURL" => "https://x", "createdAt" => "2026-01-02T03:04:05Z",
      "documentGroup" => { "eid" => "dg", "signers" => [{ "eid" => "s1", "aliasId" => "a" }] }
    )

    expect(packet.details_url).to eq("https://x")
    expect(packet.created_at).to eq(Time.utc(2026, 1, 2, 3, 4, 5))
    expect(packet.document_group).to be_a(Anvil::Types::DocumentGroup)
    expect(packet.signers.first).to be_a(Anvil::Types::Signer)
    expect(packet.signers.first.alias_id).to eq("a")
  end

  it "sends operation arguments under the API's own names, nested input types included" do
    args = Anvil::Operations::CreateEtchPacketArgs.new(
      is_test: true, webhook_url: "https://hook", merge_pdfs: false,
      files: [Anvil::Payloads::EtchFile.new(id: "f", cast_eid: "c")]
    )

    expect(args.to_h).to eq(
      "isTest" => true, "webhookURL" => "https://hook", "mergePDFs" => false,
      "files" => [{ "id" => "f", "castEid" => "c" }]
    )
  end

  it "records what the API requires, and the values it documents, on a REST payload" do
    expect(Anvil::Payloads::FillPdfRequest::REQUIRED).to eq(["data"])
    expect(Anvil::Payloads::FillPdfRequest::OUTPUT_FORMAT_VALUES).to include("pdf")
  end

  it "keeps an enum's value a plain string, so a value the API adds later still parses" do
    expect(Anvil::Types::DownloadFormat::PDF).to eq("pdf")
    expect(Anvil::Types::DownloadFormat::VALUES).to eq(%w[pdf zip])
  end

  it "renames a schema type that would shadow a Ruby core constant" do
    expect(Anvil::Types.const_defined?(:AnvilFile)).to be(true)
    expect(Anvil::Types.const_defined?(:File, false)).to be(false)
  end

  it "defines no type that shadows a Ruby core constant from inside Anvil::Types" do
    shadowed = Anvil::Types.constants(false).select { |c| Object.const_defined?(c, false) && Anvil::Types.const_get(c) != Object.const_get(c) }
    expect(shadowed).to eq([]), "rename these in dev/generate-types.mjs RENAMES: #{shadowed.join(", ")}"
  end

  it "suffixes an attribute whose name Ruby already owns, keeping the API's key" do
    attributes = Anvil::Types::BillingPeriod.attributes
    expect(attributes).to have_key(:end_value)
    expect(attributes[:end_value][:key]).to eq("end")
  end

  it "lets the hand-written classes add to the generated ones rather than redefine them" do
    expect(Anvil::Payloads::CreateEtchPacket.superclass).to eq(Anvil::Operations::CreateEtchPacketArgs)
    expect(Anvil::Payloads::FillPdf.superclass).to eq(Anvil::Payloads::FillPdfRequest)
    expect(Anvil::Types::EtchPacket.new.signers).to eq([])
  end
end
