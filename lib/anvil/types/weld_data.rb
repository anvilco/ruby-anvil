# frozen_string_literal: true

module Anvil
  module Types
    # A Workflow submission's collected data.
    class WeldData < Base
      attribute :id
      attribute :eid
      attribute :is_test
      attribute :is_complete
      attribute :agents
    end
  end
end
