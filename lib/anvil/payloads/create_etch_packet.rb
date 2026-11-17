# frozen_string_literal: true

module Anvil
  module Payloads
    # The variables of a {Anvil::Client#create_etch_packet} call.
    #
    # @see https://www.useanvil.com/docs/api/e-signatures
    class CreateEtchPacket < Base
      attribute :name
      attribute :organization_eid
      # @return [Array<EtchFile>]
      attribute :files, array_of: EtchFile
      # @return [Boolean] true to leave the packet in the dashboard for review
      #   instead of sending it
      attribute :is_draft
      # @return [Boolean] true for a test packet, which uses development
      #   signatures and is not billed
      attribute :is_test
      attribute :signature_email_subject
      attribute :signature_email_body
      attribute :signature_provider
      attribute :signature_page_options
      # @return [Array<EtchSigner>]
      attribute :signers, array_of: EtchSigner
      # @return [Hash] values to fill into the packet's files before sending
      attribute :data
      attribute :webhook_url, key: "webhookURL"
      attribute :reply_to_name
      attribute :reply_to_email
      attribute :enable_emails
      attribute :create_cast_templates_from_uploads
      attribute :duplicate_casts
      attribute :merge_pdfs, key: "mergePDFs"
      attribute :allow_updates
    end
  end
end
