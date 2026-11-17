# frozen_string_literal: true

module Anvil
  module Types
    # An Etch e-sign packet.
    class EtchPacket < Base
      attribute :id
      attribute :eid
      attribute :name
      attribute :status
      attribute :is_test
      attribute :allow_updates
      attribute :number_remaining_signers
      attribute :details_url, key: "detailsURL"
      attribute :webhook_url, key: "webhookURL"
      attribute :completed_at, type: :time
      attribute :archived_at, type: :time
      attribute :created_at, type: :time
      attribute :updated_at, type: :time
      attribute :document_group, type: DocumentGroup

      # @return [Array<Signer>] the packet's signers, or an empty array when
      #   the response query did not select them
      def signers
        document_group&.signers || []
      end
    end
  end
end
