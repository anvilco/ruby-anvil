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
