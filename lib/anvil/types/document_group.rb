# frozen_string_literal: true

module Anvil
  module Types
    # The documents an Etch packet is made of, and who signs them.
    class DocumentGroup < Base
      attribute :id
      attribute :eid
      attribute :status
      # The API returns this as JSON, so it stays a plain Array of Hashes
      attribute :files
      attribute :signers, array_of: Signer
    end
  end
end
