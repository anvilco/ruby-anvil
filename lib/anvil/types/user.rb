# frozen_string_literal: true

module Anvil
  module Types
    # An organization the current user belongs to.
    class Organization < Base
      attribute :id
      attribute :eid
      attribute :name
      attribute :slug
    end

    # Whoever the API key or access token belongs to.
    class User < Base
      attribute :id
      attribute :eid
      attribute :name
      attribute :email
      attribute :role
      attribute :organizations, array_of: Organization
    end
  end
end
