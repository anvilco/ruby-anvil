# frozen_string_literal: true

module Anvil
  module Types
    # Every field is generated from the schema in generated/graphql.rb; this
    # adds what the API's shape does not say outright.
    class EtchPacket
      # @return [Array<Signer>] the packet's signers, or an empty array when
      #   the response query did not select them
      def signers
        document_group&.signers || []
      end
    end
  end
end
