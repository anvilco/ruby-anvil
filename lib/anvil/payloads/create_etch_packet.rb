# frozen_string_literal: true

module Anvil
  module Payloads
    # The variables of a {Anvil::Client#create_etch_packet} call. Every argument
    # is generated from the schema into {Anvil::Operations::CreateEtchPacketArgs};
    # this is the name the client's API uses for it.
    #
    # @see https://www.useanvil.com/docs/api/e-signatures
    class CreateEtchPacket < Anvil::Operations::CreateEtchPacketArgs
    end
  end
end
