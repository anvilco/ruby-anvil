# frozen_string_literal: true

module Anvil
  module Types
    # A signer on an Etch packet's document group.
    class Signer < Base
      attribute :id
      attribute :eid
      attribute :alias_id
      attribute :routing_order
      attribute :name
      attribute :email
      attribute :status
      attribute :sign_action_type
    end
  end
end
