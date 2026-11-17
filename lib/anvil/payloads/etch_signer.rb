# frozen_string_literal: true

module Anvil
  module Payloads
    # One field a signer signs or fills, on one of the packet's files.
    class SignerField < Base
      # @return [String] the `id` of the {EtchFile} this field is on
      attribute :file_id
      # @return [String] the field's id on that PDF template
      attribute :field_id
    end

    # A signer on a {CreateEtchPacket}. Signers sign in the order they appear
    # in the packet's `signers`, unless `routing_order` says otherwise.
    class EtchSigner < Base
      # @return [String] your own id for this signer, referenced elsewhere in the packet
      attribute :id
      attribute :name
      attribute :email
      # @return [String] "email" for a signature request by email, or "embedded"
      #   to generate a signing URL yourself with {Anvil::Client#generate_etch_sign_url}
      attribute :signer_type
      attribute :routing_order
      # @return [Array<SignerField>] the fields this signer clicks through, in order
      attribute :fields, array_of: SignerField
      attribute :redirect_url, key: "redirectURL"
      attribute :enable_emails
      attribute :accept_each_field
      attribute :signature_mode
    end
  end
end
