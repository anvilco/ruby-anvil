# frozen_string_literal: true

module Anvil
  module Payloads
    # One field a signer signs or fills, on one of the packet's files. The API
    # takes signer fields as JSON, so this is the one payload with no schema
    # type behind it.
    class SignerField < Base
      # @return [String] the `id` of the {EtchFile} this field is on
      attribute :file_id
      # @return [String] the field's id on that PDF template
      attribute :field_id
    end

    # A signer on a {CreateEtchPacket}. Every field is generated from the
    # OpenAPI spec in generated/rest.rb. Signers sign in the order they appear
    # in the packet's `signers`, unless `routing_order` says otherwise.
    class EtchSigner
      # Reopened to carry the documentation above
    end
  end
end
