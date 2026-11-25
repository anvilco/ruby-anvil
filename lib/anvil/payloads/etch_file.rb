# frozen_string_literal: true

module Anvil
  module Payloads
    # A file in an Etch packet: either an existing PDF template (`cast_eid`) or
    # a PDF you upload with the packet (`file`). Every field is generated from
    # the schema in generated/operations.rb.
    #
    # Upload a new PDF by passing {Anvil.prepare_graphql_file} as `file`:
    #
    #   Anvil::Payloads::EtchFile.new(
    #     id: "contract",
    #     title: "Contract",
    #     file: Anvil.prepare_graphql_file("./contract.pdf"),
    #     fields: [{ id: "signature", type: "signature", pageNum: 0, rect: { ... } }]
    #   )
    class EtchFile
      # Reopened to carry the documentation above
    end
  end
end
