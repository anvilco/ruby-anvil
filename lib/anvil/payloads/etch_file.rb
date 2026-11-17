# frozen_string_literal: true

module Anvil
  module Payloads
    # A file in an Etch packet: either an existing PDF template (`cast_eid`) or
    # a PDF you upload with the packet (`file`).
    #
    # Upload a new PDF by passing {Anvil.prepare_graphql_file} as `file`:
    #
    #   Anvil::Payloads::EtchFile.new(
    #     id: "contract",
    #     title: "Contract",
    #     file: Anvil.prepare_graphql_file("./contract.pdf"),
    #     fields: [{ id: "signature", type: "signature", pageNum: 1, rect: { ... } }]
    #   )
    class EtchFile < Base
      # @return [String] your own id for this file, referenced by the packet's
      #   `data` and by each signer's fields
      attribute :id
      # @return [String] the eid of a PDF template already in your organization
      attribute :cast_eid
      attribute :title
      # @return [Anvil::UploadWithOptions, Hash] a PDF to upload with the packet
      attribute :file
      attribute :filename
      # @return [Array<Hash>] the fields to place on an uploaded PDF
      attribute :fields
      attribute :include_fields
      attribute :page_count
    end
  end
end
